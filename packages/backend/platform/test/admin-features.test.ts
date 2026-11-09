import { env } from "cloudflare:workers";
import { Effect, Layer, Scope } from "effect";
import { beforeAll, describe, expect, it } from "vitest";
import { AdminData } from "@billet/backend-admin/admin-data";
import { buildFeatureUsage, featureAreas } from "@billet/backend-admin/admin-features";
import { makeSeed, seedStatements } from "@billet/backend-admin/seed-data";
import { AdminDataLive } from "../src/admin-data-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const today = "2026-11-04";

const adminData = () =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(AdminDataLive(env.DB), yield* Scope.make());
      return context.mapUnsafe.get(AdminData.key) as AdminData["Service"];
    }),
  );

/**
 * Hand-checked: per variant (or `*`), pairs with a row from `from` on, and those with `names`.
 */
const usageSql = (names: ReadonlyArray<string>) => {
  const list = names.map((name) => `'${name}'`).join(", ");
  const window = "e.pair_id <> '' AND e.day >= ?1 AND e.day <= ?2";
  return `
    SELECT '*' AS variant, COUNT(DISTINCT e.pair_id) AS active,
      COUNT(DISTINCT CASE WHEN e.name IN (${list}) THEN e.pair_id END) AS used
    FROM pair_events e WHERE ${window}
    UNION ALL
    SELECT f.variant, COUNT(DISTINCT e.pair_id),
      COUNT(DISTINCT CASE WHEN e.name IN (${list}) THEN e.pair_id END)
    FROM pair_events e JOIN pair_flags f ON f.pair_id = e.pair_id AND f.experiment_key = 'home-layout'
    WHERE ${window} GROUP BY f.variant`;
};

describe("feature usage against SQL, on the seed", () => {
  beforeAll(async () => {
    await resetDirectory();
    const statements = seedStatements(makeSeed({ today }), { eventBuild: true });
    await env.DB.batch(statements.map((sql) => env.DB.prepare(sql)));
  });

  it("matches the hand-written query for every row, window and variant", async () => {
    const data = await adminData();
    const [events, flags] = await Effect.runPromise(Effect.all([data.events, data.assignments]));
    const usage = buildFeatureUsage(events, flags, today, { split: "home-layout" });
    expect(usage.groups.map(({ variant }) => variant)).toEqual([null, "classic", "immersive"]);

    let compared = 0;
    for (const entry of usage.rows) {
      const names =
        entry.event === null
          ? (featureAreas.find(({ area }) => area === entry.area)?.events ?? [])
          : [entry.event];
      for (const window of ["d7", "d30"] as const) {
        const { results } = await env.DB.prepare(usageSql(names))
          .bind(usage.from[window], today)
          .all<{ variant: string; active: number; used: number }>();
        const byVariant = new Map(results.map((result) => [result.variant, result]));
        for (const [index, group] of usage.groups.entries()) {
          const expected = byVariant.get(group.variant ?? "*");
          const cell = entry.cells[index]?.[window];
          if (expected === undefined || expected.used < 5 || expected.active < 5) {
            expect(cell).toBeNull();
            continue;
          }
          expect(cell).toMatchObject({
            count: expected.used,
            of: expected.active,
            share: expected.used / expected.active,
          });
          compared += 1;
        }
      }
    }
    // Most rows carry real numbers on the seed.
    expect(compared).toBeGreaterThan(40);
  });
});
