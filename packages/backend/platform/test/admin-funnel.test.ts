import { env } from "cloudflare:workers";
import { Effect, Layer, Scope } from "effect";
import { beforeAll, describe, expect, it } from "vitest";
import { AdminData } from "@billet/backend-admin/admin-data";
import { buildFunnel, type FunnelDefinition } from "@billet/backend-admin/admin-funnel";
import { FunnelStore } from "@billet/backend-admin/funnel-store";
import { makeSeed, seedStatements } from "@billet/backend-admin/seed-data";
import { AdminDataLive } from "../src/admin-data-live.ts";
import { FunnelStoreLive } from "../src/funnel-store-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const today = "2026-11-04";
const day = 86_400_000;

const service = <S, I>(layer: Layer.Layer<I>, key: { readonly key: string }) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(layer, yield* Scope.make());
      return context.mapUnsafe.get(key.key) as S;
    }),
  );

const deadline = (window: FunnelDefinition["window"], t: string) =>
  window === "day"
    ? `((${t} / ${day}) * ${day} + ${day} - 1)`
    : `(${t} + ${window === "1d" ? day : 7 * day})`;

/**
 * Hand-checked: each later step's first moment after the one before, within step 1's window.
 */
const funnelSql = (definition: FunnelDefinition, from: string | null) => {
  const unit = definition.unit === "pair" ? "pair_id" : "user_id";
  const steps = definition.steps.map((_, index) => {
    if (index === 0) {
      return `s0 AS (SELECT unit, MIN(first_at) AS t0 FROM ev WHERE name = ?1
        ${from === null ? "" : "AND day >= ?2"} AND day <= ?3 GROUP BY unit)`;
    }
    const before = `s${index - 1}`;
    const keep = Array.from({ length: index }, (_, k) => `${before}.t${k}`).join(", ");
    return `${`s${index}`}_all AS (
        SELECT ${before}.unit, ${keep},
          MIN(CASE WHEN e.first_at >= ${before}.t${index - 1} THEN e.first_at ELSE e.last_at END) AS t${index}
        FROM ${before} JOIN ev e ON e.unit = ${before}.unit AND e.name = ?${index + 3}
          AND e.last_at >= ${before}.t${index - 1}
        GROUP BY ${before}.unit, ${keep}),
      s${index} AS (SELECT * FROM s${index}_all WHERE t${index} <= ${deadline(definition.window, "t0")})`;
  });
  return `WITH ev AS (SELECT ${unit} AS unit, name, day, first_at, last_at FROM pair_events WHERE ${unit} <> ''),
    ${steps.join(",\n    ")}
    SELECT * FROM s${definition.steps.length - 1}`;
};

const median = (values: ReadonlyArray<number>) => {
  const sorted = values.toSorted((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1
    ? sorted[middle]
    : ((sorted[middle - 1] ?? 0) + (sorted[middle] ?? 0)) / 2;
};

describe("funnel builder against SQL, on the seed", () => {
  beforeAll(async () => {
    await resetDirectory();
    const statements = seedStatements(makeSeed({ today }), { eventBuild: true });
    await env.DB.batch(statements.map((sql) => env.DB.prepare(sql)));
  });

  const definitions: ReadonlyArray<[FunnelDefinition, "30" | "90" | "all"]> = [
    [{ steps: ["PairClaimed", "NoteSent", "WidgetAdded"], window: "7d", unit: "pair" }, "all"],
    [{ steps: ["AppOpened", "CatPetted"], window: "day", unit: "person" }, "30"],
    [
      { steps: ["ShopOpened", "ShopItemViewed", "ShopItemBought"], window: "1d", unit: "person" },
      "90",
    ],
    [
      {
        steps: ["InviteCreated", "PairClaimed", "NoteSent", "StreakOpened"],
        window: "7d",
        unit: "person",
      },
      "all",
    ],
  ];

  it.each(definitions)(
    "matches the hand-written query: %j over %s days",
    async (definition, range) => {
      const data = await service<AdminData["Service"], AdminData>(AdminDataLive(env.DB), AdminData);
      const [events, flags] = await Effect.runPromise(Effect.all([data.events, data.assignments]));
      const result = buildFunnel(events, flags, today, definition, { range });
      const from = result.from;

      for (const [index] of definition.steps.entries()) {
        const prefix = { ...definition, steps: definition.steps.slice(0, index + 1) };
        const { results } = await env.DB.prepare(funnelSql(prefix, from))
          .bind(definition.steps[0], from, today, ...definition.steps.slice(1, index + 1))
          .all<Record<string, number>>();
        const step = result.groups[0]?.steps[index];
        if (results.length < 5) {
          expect(step?.count).toBeNull();
          continue;
        }
        expect(step?.count).toBe(results.length);
        if (index > 0) {
          expect(step?.medianFromPrevious).toBe(
            median(results.map((row) => (row[`t${index}`] ?? 0) - (row[`t${index - 1}`] ?? 0))),
          );
        }
      }
      // Each funnel has a first step with a real number in it.
      expect(result.groups[0]?.entered).toBeGreaterThan(5);
    },
  );

  it("splits per pair by variant, against SQL", async () => {
    const data = await service<AdminData["Service"], AdminData>(AdminDataLive(env.DB), AdminData);
    const [events, flags] = await Effect.runPromise(Effect.all([data.events, data.assignments]));
    const definition: FunnelDefinition = {
      steps: ["PairClaimed", "NoteSent"],
      window: "1d",
      unit: "pair",
    };
    const result = buildFunnel(events, flags, today, definition, {
      range: "all",
      split: "home-layout",
    });
    const { results } = await env.DB.prepare(
      `SELECT f.variant, COUNT(*) AS converted FROM (${funnelSql(definition, null)}) s
       JOIN pair_flags f ON f.pair_id = s.unit AND f.experiment_key = 'home-layout'
       GROUP BY f.variant ORDER BY f.variant`,
    )
      .bind("PairClaimed", null, today, "NoteSent")
      .all<{ variant: string; converted: number }>();
    expect(result.groups.slice(1).map((group) => [group.variant, group.steps[1]?.count])).toEqual(
      results.map(({ variant, converted }) => [variant, converted]),
    );
  });
});

describe("FunnelStore on D1", () => {
  it("saves, lists newest first and removes", async () => {
    await resetDirectory();
    const store = await service<FunnelStore["Service"], FunnelStore>(
      FunnelStoreLive(env.DB),
      FunnelStore,
    );
    const definition: FunnelDefinition = {
      steps: ["AppOpened", "NoteSent"],
      window: "day",
      unit: "person",
    };
    const older = {
      id: "00000000-0000-4000-8000-000000000001",
      name: "Open to note",
      definition,
      createdAt: 1,
      createdBy: "owner@example.com",
    };
    const newer = { ...older, id: "00000000-0000-4000-8000-000000000002", createdAt: 2 };
    await Effect.runPromise(store.save(older));
    await Effect.runPromise(store.save(newer));
    expect(await Effect.runPromise(store.all)).toEqual([newer, older]);
    expect(await Effect.runPromise(store.remove(older.id))).toBe(true);
    expect(await Effect.runPromise(store.remove(older.id))).toBe(false);
    // A row whose definition no longer decodes (an event that was removed) is left out.
    await env.DB.prepare(
      "INSERT INTO admin_funnels (id, name, definition, created_at, created_by) VALUES (?, ?, ?, ?, ?)",
    )
      .bind("old", "Old", JSON.stringify({ ...definition, steps: ["Gone", "NoteSent"] }), 3, "x")
      .run();
    expect(await Effect.runPromise(store.all)).toEqual([newer]);
  });
});
