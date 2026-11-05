import { env } from "cloudflare:workers";
import { Effect, Layer, Scope } from "effect";
import { beforeAll, describe, expect, it } from "vitest";
import { AdminData } from "@billet/backend-admin/admin-data";
import {
  buildRetentionGrid,
  minimumGroup,
  retentionDays,
  retentionModes,
  type RetentionMode,
} from "@billet/backend-admin/admin-retention";
import { makeSeed, seedStatements } from "@billet/backend-admin/seed-data";
import { AdminDataLive } from "../src/admin-data-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const today = "2026-11-04";
const seed = makeSeed({ today });

const adminData = () =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(AdminDataLive(env.DB), yield* Scope.make());
      return context.mapUnsafe.get(AdminData.key) as AdminData["Service"];
    }),
  );

// The hand-checked query: per week the pair formed (Monday, UTC) and day N, the pairs that have
// reached day N and how many of them meet the mode. Written apart from `buildRetentionGrid`, in
// SQL, so the two only agree if both read the rows the same way.
const retentionSql = (mode: RetentionMode) => {
  const names = mode === "bothNote" ? "('NoteSent')" : "('AppOpened', 'NoteSent')";
  const meets = mode === "either" ? "hits >= 1" : "hits = 2 AND size = 2";
  return `
    WITH claims AS (
      SELECT pair_id, user_id, day FROM pair_events WHERE name = 'PairClaimed' AND pair_id <> ''
    ),
    pairs AS (SELECT pair_id, MIN(day) AS formed FROM claims GROUP BY pair_id),
    members AS (SELECT DISTINCT pair_id, user_id FROM claims),
    sizes AS (SELECT pair_id, COUNT(*) AS size FROM members GROUP BY pair_id),
    present AS (
      SELECT DISTINCT pair_id, user_id, day FROM pair_events
      WHERE name IN ${names} AND pair_id <> ''
    ),
    reached AS (
      SELECT p.pair_id, p.formed, s.size,
        (SELECT COUNT(*) FROM members m JOIN present a
           ON a.pair_id = m.pair_id AND a.user_id = m.user_id
          WHERE m.pair_id = p.pair_id AND a.day = date(p.formed, '+' || ?1 || ' days')) AS hits
      FROM pairs p JOIN sizes s ON s.pair_id = p.pair_id
      WHERE p.formed <= ?2 AND date(p.formed, '+' || ?1 || ' days') <= ?2
    )
    SELECT date(formed, '-' || ((CAST(strftime('%w', formed) AS INTEGER) + 6) % 7) || ' days') AS week,
      COUNT(*) AS reached,
      SUM(CASE WHEN ${meets} THEN 1 ELSE 0 END) AS met
    FROM reached GROUP BY week`;
};

describe("retention grid against SQL, on the seed", () => {
  beforeAll(async () => {
    await resetDirectory();
    const statements = seedStatements(seed, { eventBuild: true });
    await env.DB.batch(statements.map((sql) => env.DB.prepare(sql)));
  });

  it("matches the hand-written query in every week, day and mode", async () => {
    const data = await adminData();
    const [events, flags] = await Effect.runPromise(Effect.all([data.events, data.assignments]));
    const grid = buildRetentionGrid(events, flags, today);

    let compared = 0;
    for (const mode of retentionModes) {
      for (const [column, n] of retentionDays.entries()) {
        const { results } = await env.DB.prepare(retentionSql(mode))
          .bind(n, today)
          .all<{ week: string; reached: number; met: number }>();
        const byWeek = new Map(results.map((row) => [row.week, row]));
        for (const row of grid.rows.filter(({ week }) => week !== "all")) {
          const cell = row.cells[mode][column];
          const expected = byWeek.get(row.week);
          if (expected === undefined) {
            expect(cell).toEqual({ state: "pending" });
          } else if (expected.reached < minimumGroup) {
            expect(cell).toEqual({ state: "too-few" });
          } else {
            expect(cell).toMatchObject({
              state: "value",
              count: expected.met,
              of: expected.reached,
            });
            compared += 1;
          }
        }
      }
    }
    // The seed is big enough that most cells carry a number.
    expect(compared).toBeGreaterThan(100);
  });

  it("filters by variant against SQL", async () => {
    const data = await adminData();
    const [events, flags] = await Effect.runPromise(Effect.all([data.events, data.assignments]));
    const grid = buildRetentionGrid(events, flags, today, {
      variant: { key: "home-layout", variant: "immersive" },
    });
    const { results } = await env.DB.prepare(
      `SELECT COUNT(DISTINCT e.pair_id) AS pairs FROM pair_events e
       JOIN pair_flags f ON f.pair_id = e.pair_id
       WHERE e.name = 'PairClaimed' AND f.experiment_key = 'home-layout' AND f.variant = 'immersive'`,
    ).all<{ pairs: number }>();
    expect(grid.rows.at(-1)?.pairs).toBe(results[0]?.pairs);
  });

  it("filters by the build a pair formed on, against SQL", async () => {
    const data = await adminData();
    const [events, flags] = await Effect.runPromise(Effect.all([data.events, data.assignments]));
    // A pair's build: its earliest row that carries one (the server's own rows carry none).
    const { results } = await env.DB.prepare(
      `WITH formed AS (SELECT DISTINCT pair_id FROM pair_events WHERE name = 'PairClaimed'),
       ranked AS (
         SELECT pair_id, app_version,
           ROW_NUMBER() OVER (PARTITION BY pair_id ORDER BY first_at, user_id) AS n
         FROM pair_events WHERE pair_id <> '' AND app_version IS NOT NULL
       )
       SELECT COALESCE(r.app_version, 'unknown') AS version, COUNT(*) AS pairs
       FROM formed f LEFT JOIN ranked r ON r.pair_id = f.pair_id AND r.n = 1
       GROUP BY version`,
    ).all<{ version: string; pairs: number }>();
    const all = buildRetentionGrid(events, flags, today);
    expect(all.options.appVersions).toEqual(results.map(({ version }) => version).toSorted());
    expect(results.length).toBeGreaterThan(2);
    for (const { version, pairs } of results) {
      const grid = buildRetentionGrid(events, flags, today, { appVersion: version });
      expect(grid.rows.at(-1)?.pairs).toBe(pairs < minimumGroup ? null : pairs);
    }
  });
});
