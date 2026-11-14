import { describe, expect, it } from "vitest";
import {
  buildTrends,
  engineCanAnswer,
  engineSql,
  type EngineRow,
  type TrendQuery,
} from "../src/admin-trends.ts";
import type { BuildEventRow } from "../src/admin-retention.ts";

const today = "2026-11-04";

/** `n` pairs who each opened the app once on `day`, on `appVersion`. */
const opens = (
  n: number,
  day: string,
  appVersion = "1.2.0+14",
  prefix = "p",
): Array<BuildEventRow> =>
  Array.from({ length: n }, (_, i) => ({
    pairId: `${prefix}${i}`,
    userId: `${prefix}${i}-a`,
    name: "AppOpened" as const,
    day,
    count: 2,
    firstAt: Date.parse(`${day}T09:00:00Z`),
    appVersion,
    os: "iOS 26.1",
  }));

const base: TrendQuery = {
  event: "AppOpened",
  metric: "count",
  interval: "day",
  range: "30",
  split: "none",
};

describe("buildTrends", () => {
  it("counts per day, hides a day under 5 pairs, and lines up the period before", () => {
    const events = [
      ...opens(6, "2026-11-04"),
      ...opens(3, "2026-11-03"),
      ...opens(5, "2026-10-05"),
    ];
    const trends = buildTrends(events, [], today, base);
    expect(trends.from).toBe("2026-10-06");
    expect(trends.previousFrom).toBe("2026-09-06");
    const points = trends.groups[0]?.points ?? [];
    expect(points).toHaveLength(30);
    expect(points.at(-1)).toMatchObject({ start: today, value: 12, previous: 10, source: "d1" });
    expect(points.at(-2)?.value).toBeNull();
    expect(trends.groups[0]).toMatchObject({ group: "all", total: 18, previousTotal: 10 });
    expect(trends.engine).toBe("unavailable");
  });

  it("measures people, pairs and count per pair", () => {
    const events = opens(5, "2026-11-04");
    const value = (metric: TrendQuery["metric"]) =>
      buildTrends(events, [], today, { ...base, metric }).groups[0]?.points.at(-1)?.value;
    expect([value("count"), value("people"), value("pairs"), value("perPair")]).toEqual([
      10, 5, 5, 2,
    ]);
  });

  it("gives a server-recorded row the person's build from that day", () => {
    const events: Array<BuildEventRow> = [
      ...opens(5, "2026-11-04", "1.3.0+17"),
      ...Array.from({ length: 5 }, (_, i) => ({
        pairId: `p${i}`,
        userId: `p${i}-a`,
        name: "NoteSent" as const,
        day: "2026-11-04",
        count: 1,
        firstAt: 0,
        appVersion: null,
      })),
    ];
    const trends = buildTrends(events, [], today, { ...base, event: "NoteSent", split: "version" });
    expect(trends.groups.map(({ group }) => group)).toEqual(["1.3.0+17"]);
  });

  it("keeps the eight biggest groups and adds up the rest as other", () => {
    const events = Array.from({ length: 10 }, (_, v) =>
      opens(5 + v, "2026-11-04", `1.${v}.0+${v}`, `v${v}-`),
    ).flat();
    const trends = buildTrends(events, [], today, { ...base, split: "version" });
    expect(trends.groups).toHaveLength(9);
    expect(trends.groups[0]?.group).toBe("1.9.0+9");
    expect(trends.groups.at(-1)).toMatchObject({ group: "other", total: (5 + 6) * 2 });
  });

  it("takes Analytics Engine's answer for its last 90 days and D1 before, never under 5 pairs", () => {
    const engine: Array<EngineRow> = [
      { day: "2026-11-04", group: "", count: 40, pairs: 9 },
      { day: "2026-11-03", group: "", count: 8, pairs: 4 },
    ];
    const events = [...opens(6, "2026-11-04"), ...opens(6, "2026-06-01")];
    const trends = buildTrends(events, [], today, { ...base, range: "180" }, { rows: engine });
    expect(trends.engine).toBe("used");
    const points = trends.groups[0]?.points ?? [];
    expect(points.at(-1)).toMatchObject({ value: 40, source: "analytics-engine" });
    expect(points.at(-2)).toMatchObject({ value: null, source: "analytics-engine" });
    const old = points.find(({ start }) => start === "2026-06-01");
    expect(old).toMatchObject({ value: 12, source: "d1" });
    // The day 90 days back is the first from Analytics Engine; the one before is from D1.
    expect(points.find(({ start }) => start === "2026-08-07")?.source).toBe("analytics-engine");
    expect(points.find(({ start }) => start === "2026-08-06")?.source).toBe("d1");
  });

  it("uses D1 alone for what Analytics Engine cannot answer", () => {
    expect(engineCanAnswer(base)).toBe(true);
    expect(engineCanAnswer({ ...base, metric: "people" })).toBe(false);
    expect(engineCanAnswer({ ...base, metric: "pairs", interval: "week" })).toBe(false);
    expect(engineCanAnswer({ ...base, split: "variant", key: "home-layout" })).toBe(false);
    expect(engineCanAnswer({ ...base, event: "NoteSent" })).toBe(false);
    const trends = buildTrends(
      opens(5, today),
      [],
      today,
      { ...base, metric: "people" },
      {
        rows: [{ day: today, group: "", count: 99, pairs: 99 }],
      },
    );
    expect(trends.engine).toBe("not-applicable");
    expect(trends.groups[0]?.points.at(-1)).toMatchObject({ value: 5, source: "d1" });
  });
});

describe("engineSql", () => {
  it("is one SELECT over the stage's dataset, by day and the split column", () => {
    const sql = engineSql("billet_dev_events", { ...base, split: "os" }, "2026-08-07", today);
    expect(sql).toMatch(
      /^SELECT toStartOfInterval\(timestamp, INTERVAL '1' DAY\) AS day, blob5 AS grp/,
    );
    expect(sql).toContain("FROM billet_dev_events WHERE blob1 = 'AppOpened'");
    expect(sql).toContain("GROUP BY day, grp");
  });

  it("refuses anything that did not come from the closed lists", () => {
    expect(() => engineSql("billet_dev_events; DROP", base, "2026-08-07", today)).toThrow();
    expect(() => engineSql("Ourio_prod_events", base, "2026-08-07", today)).toThrow();
    expect(engineSql("ourio_prod_events", base, "2026-08-07", today)).toContain(
      "FROM ourio_prod_events",
    );
    expect(() =>
      engineSql("billet_dev_events", { ...base, event: "x' OR '1'='1" }, "2026-08-07", today),
    ).toThrow();
    expect(() => engineSql("billet_dev_events", base, "2026-08-07'", today)).toThrow();
  });
});
