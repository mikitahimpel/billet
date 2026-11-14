import { env } from "cloudflare:workers";
import { Effect, Layer, Option, Scope } from "effect";
import { beforeAll, describe, expect, it } from "vitest";
import { AdminData } from "@billet/backend-admin/admin-data";
import { buildTrends, type TrendQuery } from "@billet/backend-admin/admin-trends";
import { AnalyticsEngineReader } from "@billet/backend-admin/analytics-engine-reader";
import { makeSeed, seedStatements } from "@billet/backend-admin/seed-data";
import { AdminDataLive } from "../src/admin-data-live.ts";
import { AnalyticsEngineReaderLive } from "../src/analytics-engine-reader-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const today = "2026-11-04";

const adminData = () =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(AdminDataLive(env.DB), yield* Scope.make());
      return context.mapUnsafe.get(AdminData.key) as AdminData["Service"];
    }),
  );

// The hand-checked query: per group and day (or Monday), the count, people, pairs, and the pairs
// or (before pairing) people behind it. A server-recorded row takes the person's build that day.
const trendSql = (query: TrendQuery) => {
  const start =
    query.interval === "week"
      ? "date(day, '-' || ((CAST(strftime('%w', day) AS INTEGER) + 6) % 7) || ' days')"
      : "day";
  const build = (column: "app_version" | "os") =>
    `COALESCE(e.${column}, (SELECT o.${column} FROM pair_events o WHERE o.user_id = e.user_id
       AND o.day = e.day AND o.${column} IS NOT NULL LIMIT 1), 'unknown')`;
  const group =
    query.split === "version"
      ? build("app_version")
      : query.split === "os"
        ? build("os")
        : query.split === "variant"
          ? `COALESCE((SELECT f.variant FROM pair_flags f WHERE f.pair_id = e.pair_id
               AND f.experiment_key = ?4), 'not in it')`
          : "'all'";
  return `SELECT ${group} AS grp, ${start} AS start,
      SUM(count) AS count, COUNT(DISTINCT user_id) AS people,
      COUNT(DISTINCT NULLIF(pair_id, '')) AS pairs,
      COUNT(DISTINCT CASE WHEN pair_id = '' THEN 'person:' || user_id ELSE pair_id END) AS units
    FROM pair_events e WHERE name = ?1 AND day >= ?2 AND day <= ?3
    GROUP BY grp, start`;
};

const queries: ReadonlyArray<TrendQuery> = [
  { event: "AppOpened", metric: "count", interval: "day", range: "30", split: "none" },
  { event: "NoteSent", metric: "people", interval: "week", range: "90", split: "version" },
  { event: "CatPetted", metric: "pairs", interval: "day", range: "30", split: "os" },
  {
    event: "NoteSent",
    metric: "perPair",
    interval: "week",
    range: "90",
    split: "variant",
    key: "home-layout",
  },
  { event: "InviteCreated", metric: "people", interval: "week", range: "180", split: "none" },
];

describe("trends against SQL, on the seed", () => {
  beforeAll(async () => {
    await resetDirectory();
    const statements = seedStatements(makeSeed({ today }), { eventBuild: true });
    await env.DB.batch(statements.map((sql) => env.DB.prepare(sql)));
  });

  it.each(queries)("matches the hand-written query: %j", async (query) => {
    const data = await adminData();
    const [events, flags] = await Effect.runPromise(Effect.all([data.events, data.assignments]));
    const trends = buildTrends(events, flags, today, query);
    const { results } = await env.DB.prepare(trendSql(query))
      .bind(
        query.event,
        trends.previousFrom,
        today,
        ...(query.key === undefined ? [] : [query.key]),
      )
      .all<{
        grp: string;
        start: string;
        count: number;
        people: number;
        pairs: number;
        units: number;
      }>();
    const expected = new Map(results.map((row) => [`${row.grp}|${row.start}`, row]));
    const valueOf = (row: (typeof results)[number] | undefined) => {
      if (row === undefined || row.units < 5) return null;
      if (query.metric === "perPair") return row.pairs < 5 ? null : row.count / row.pairs;
      return row[query.metric];
    };

    let compared = 0;
    for (const group of trends.groups) {
      for (const point of group.points) {
        expect(point.source).toBe("d1");
        expect(point.value).toBe(valueOf(expected.get(`${group.group}|${point.start}`)));
        if (point.value !== null) compared += 1;
      }
    }
    expect(compared).toBeGreaterThan(3);
    // Every group the query finds is shown (the seed has fewer than eight of each).
    expect(trends.groups.map(({ group }) => group).toSorted()).toEqual(
      [...new Set(results.map(({ grp }) => grp))].toSorted(),
    );
  });

  it("compares with the period before: each point's previous is the same point one period back", async () => {
    const data = await adminData();
    const [events, flags] = await Effect.runPromise(Effect.all([data.events, data.assignments]));
    const query = queries[0] as TrendQuery;
    const trends = buildTrends(events, flags, today, query);
    const { results } = await env.DB.prepare(trendSql(query))
      .bind(query.event, trends.previousFrom, today)
      .all<{ start: string; count: number; units: number }>();
    const byStart = new Map(results.map((row) => [row.start, row]));
    const first = trends.groups[0]?.points[0];
    const back = byStart.get(trends.previousFrom);
    expect(first?.start).toBe(trends.from);
    expect(first?.previous).toBe(back === undefined || back.units < 5 ? null : back.count);
  });
});

describe("AnalyticsEngineReaderLive", () => {
  const config = { accountId: "0123456789abcdef0123456789abcdef", token: "t", stage: "dev" };
  const query: TrendQuery = {
    event: "AppOpened",
    metric: "count",
    interval: "day",
    range: "30",
    split: "version",
  };
  const readerOf = (layer: Layer.Layer<AnalyticsEngineReader>) =>
    Effect.runPromise(
      Effect.gen(function* () {
        const context = yield* Layer.buildWithScope(layer, yield* Scope.make());
        return context.mapUnsafe.get(AnalyticsEngineReader.key) as AnalyticsEngineReader["Service"];
      }),
    );

  it("is none without a token, an account or a stage", async () => {
    for (const partial of [
      { ...config, token: undefined },
      { ...config, accountId: "" },
      { ...config, stage: undefined },
      { ...config, stage: "Dev Stage" },
      { ...config, stack: "Ourio" },
    ]) {
      const reader = await readerOf(AnalyticsEngineReaderLive(partial, () => Promise.reject()));
      expect(Option.isNone(await Effect.runPromise(reader.trend(query, "2026-08-07", today)))).toBe(
        true,
      );
    }
  });

  it("sends one SELECT with the token, and reads numbers sent as strings", async () => {
    const sent: Array<{ url: string; init: RequestInit | undefined }> = [];
    const fetcher = (async (url: string, init?: RequestInit) => {
      sent.push({ url, init });
      return Response.json({
        data: [
          { day: "2026-11-01 00:00:00", grp: "1.2.0+14", count: "12", hashes: "6", unpaired: "1" },
        ],
      });
    }) as unknown as typeof fetch;
    const reader = await readerOf(AnalyticsEngineReaderLive(config, fetcher));
    const rows = await Effect.runPromise(reader.trend(query, "2026-08-07", today));
    expect(rows).toEqual(
      Option.some([{ day: "2026-11-01", group: "1.2.0+14", count: 12, pairs: 5 }]),
    );
    expect(sent[0]?.url).toBe(
      "https://api.cloudflare.com/client/v4/accounts/0123456789abcdef0123456789abcdef/analytics_engine/sql",
    );
    expect(sent[0]?.init?.headers).toEqual({ authorization: "Bearer t" });
    const sql = String(sent[0]?.init?.body);
    expect(sql).toMatch(/^SELECT /);
    expect(sql.match(/SELECT/g)).toHaveLength(1);
    expect(sql).toContain("FROM ourio_dev_events");
    expect(sql).toContain("blob1 = 'AppOpened'");
    expect(sql).toContain("toDateTime('2026-11-05 00:00:00')");
  });

  it("reads the stack's own dataset", async () => {
    const sent: string[] = [];
    const fetcher = (async (_url: string, init?: RequestInit) => {
      sent.push(String(init?.body));
      return Response.json({ data: [] });
    }) as unknown as typeof fetch;
    const reader = await readerOf(
      AnalyticsEngineReaderLive({ ...config, stage: "prod", stack: "ourio" }, fetcher),
    );
    await Effect.runPromise(reader.trend(query, "2026-08-07", today));
    expect(sent[0]).toContain("FROM ourio_prod_events");
  });

  it("fails with a fixed reason on an error answer, never its body", async () => {
    const reader = await readerOf(
      AnalyticsEngineReaderLive(
        config,
        (async () => new Response("secret echo", { status: 403 })) as unknown as typeof fetch,
      ),
    );
    const error = await Effect.runPromise(Effect.flip(reader.trend(query, "2026-08-07", today)));
    expect(error).toMatchObject({ _tag: "EngineUnavailable", reason: "status-403" });
    expect(JSON.stringify(error)).not.toContain("secret echo");
  });
});
