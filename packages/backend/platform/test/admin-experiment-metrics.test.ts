import { env } from "cloudflare:workers";
import { Effect, Layer, Scope } from "effect";
import { beforeAll, describe, expect, it } from "vitest";
import { AdminData } from "@billet/backend-admin/admin-data";
import { buildExperimentMetrics } from "@billet/backend-admin/admin-experiment-metrics";
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
 * The hand-checked query: per variant of `home-layout`, the pairs at least 7 days old, how many
 * had both partners active on day 7, how many had both add the widget on days 0 to 6, and the mean
 * notes and app opens per pair per day over days 0 to 6.
 */
const metricsSql = `
  WITH pairs AS (
    SELECT pair_id, MIN(day) AS formed, COUNT(DISTINCT user_id) AS members
    FROM pair_events WHERE name = 'PairClaimed' AND pair_id <> '' GROUP BY pair_id
  ),
  measured AS (
    SELECT p.pair_id, f.variant,
      p.members = 2 AND (SELECT COUNT(DISTINCT e.user_id) FROM pair_events e
        WHERE e.pair_id = p.pair_id AND e.name IN ('AppOpened', 'NoteSent')
          AND e.day = date(p.formed, '+7 days')) = 2 AS d7,
      p.members = 2 AND (SELECT COUNT(DISTINCT e.user_id) FROM pair_events e
        WHERE e.pair_id = p.pair_id AND e.name = 'WidgetAdded'
          AND e.day BETWEEN p.formed AND date(p.formed, '+6 days')) = 2 AS widget,
      (SELECT COALESCE(SUM(e.count), 0) FROM pair_events e WHERE e.pair_id = p.pair_id
        AND e.name = 'NoteSent' AND e.day BETWEEN p.formed AND date(p.formed, '+6 days')) / 7.0 AS notes,
      (SELECT COALESCE(SUM(e.count), 0) FROM pair_events e WHERE e.pair_id = p.pair_id
        AND e.name = 'AppOpened' AND e.day BETWEEN p.formed AND date(p.formed, '+6 days')) / 7.0 AS opens
    FROM pairs p JOIN pair_flags f ON f.pair_id = p.pair_id AND f.experiment_key = 'home-layout'
    WHERE date(p.formed, '+7 days') <= ?1
  )
  SELECT variant, COUNT(*) AS pairs, SUM(d7) AS d7, SUM(widget) AS widget,
    AVG(notes) AS notes, AVG(opens) AS opens
  FROM measured GROUP BY variant ORDER BY variant`;

describe("experiment metrics against SQL, on the seed", () => {
  beforeAll(async () => {
    await resetDirectory();
    const statements = seedStatements(makeSeed({ today }), { eventBuild: true });
    await env.DB.batch(statements.map((sql) => env.DB.prepare(sql)));
  });

  it("matches the hand-written query for every variant and metric", async () => {
    const data = await adminData();
    const [events, flags] = await Effect.runPromise(Effect.all([data.events, data.assignments]));
    const [result] = buildExperimentMetrics(
      events,
      flags,
      today,
      new Map([["home-layout", "classic"]]),
    );
    const { results } = await env.DB.prepare(metricsSql).bind(today).all<{
      variant: string;
      pairs: number;
      d7: number;
      widget: number;
      notes: number;
      opens: number;
    }>();
    expect(results.map(({ variant }) => variant)).toEqual(["classic", "immersive"]);
    const metric = (id: string) => result?.metrics.find((entry) => entry.id === id);

    for (const [index, expected] of results.entries()) {
      expect(expected.pairs).toBeGreaterThan(20);
      const at = (id: string) => metric(id)?.variants[index];
      expect(at("d7BothActive")?.pairs).toBe(expected.pairs);
      expect(at("d7BothActive")?.estimate?.value).toBe(expected.d7 / expected.pairs);
      expect(at("widgetAdded")?.estimate?.value).toBe(expected.widget / expected.pairs);
      expect(at("notesPerDay")?.estimate?.value).toBeCloseTo(expected.notes, 10);
      expect(at("opensPerDay")?.estimate?.value).toBeCloseTo(expected.opens, 10);
    }

    // The difference is immersive minus classic, and the seed's immersive pairs open the app less.
    const [classic, immersive] = results;
    const opens = metric("opensPerDay")?.variants[1];
    expect(opens?.vsBaseline?.value).toBeCloseTo(
      (immersive?.opens ?? 0) - (classic?.opens ?? 0),
      10,
    );
    expect(opens?.change).toBe("worse");
    expect(result?.warnings.map(({ metric: id, variant }) => [id, variant])).toEqual([
      ["opensPerDay", "immersive"],
    ]);
  });
});
