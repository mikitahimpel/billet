import { Schema } from "effect";
import { ClientEventName } from "@billet/contracts-domain/metrics";
import { addDays, type FlagRow } from "@billet/backend-metrics/funnel";
import { funnelEventNames } from "./admin-funnel.ts";
import { minimumGroup, weekOf, type BuildEventRow } from "./admin-retention.ts";

/**
 * Analytics Engine has no person, variant or server-recorded name, so those always come from D1.
 */

export const TrendMetric = Schema.Literals(["count", "people", "pairs", "perPair"]);
export type TrendMetric = typeof TrendMetric.Type;
export const TrendInterval = Schema.Literals(["day", "week"]);
export type TrendInterval = typeof TrendInterval.Type;
export const TrendRange = Schema.Literals(["30", "90", "180", "365"]);
export type TrendRange = typeof TrendRange.Type;
export const TrendSplit = Schema.Literals(["none", "variant", "version", "os"]);
export type TrendSplit = typeof TrendSplit.Type;

export const TrendEvent = Schema.String.check(
  Schema.makeFilter((name) => funnelEventNames.includes(name) || `${name} is not an event`),
);

export interface TrendQuery {
  readonly event: string;
  readonly metric: TrendMetric;
  readonly interval: TrendInterval;
  readonly range: TrendRange;
  readonly split: TrendSplit;
  readonly key?: string | undefined;
}

/** How many days Analytics Engine keeps. */
export const analyticsEngineDays = 90;

/** One day of one group as Analytics Engine answered it. `group` is empty without a split. */
export interface EngineRow {
  readonly day: string;
  readonly group: string;
  readonly count: number;
  readonly pairs: number;
}

export interface TrendPoint {
  /** The day, or the Monday of the week. */
  readonly start: string;
  /** Null when under `minimumGroup` pairs or people did it: "too few". */
  readonly value: number | null;
  /** The same point one period earlier. */
  readonly previous: number | null;
  readonly source: "d1" | "analytics-engine";
}

/**
 * The event comes from the closed list and the days are generated, so nothing typed reaches SQL.
 */
export const engineSql = (
  dataset: string,
  query: TrendQuery,
  from: string,
  today: string,
): string => {
  if (!/^[a-z][a-z0-9]*_[a-z0-9]+_events$/.test(dataset))
    throw new Error("unexpected dataset name");
  if (!funnelEventNames.includes(query.event) && query.event !== "AccountDeleted")
    throw new Error("unexpected event");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(today))
    throw new Error("unexpected day");
  const group = query.split === "version" ? "blob4" : query.split === "os" ? "blob5" : "''";
  return [
    `SELECT toStartOfInterval(timestamp, INTERVAL '1' DAY) AS day, ${group} AS grp,`,
    // Every row counts, as in D1; the unpaired ones share the empty hash, taken out of the pairs.
    `SUM(_sample_interval * double1) AS count, COUNT(DISTINCT blob2) AS hashes,`,
    `countIf(blob2 = '') AS unpaired`,
    `FROM ${dataset}`,
    `WHERE blob1 = '${query.event}'`,
    `AND timestamp >= toDateTime('${from} 00:00:00') AND timestamp < toDateTime('${addDays(today, 1)} 00:00:00')`,
    `GROUP BY day, grp`,
  ].join(" ");
};

export interface TrendGroup {
  readonly group: string;
  readonly total: number | null;
  readonly previousTotal: number | null;
  readonly points: ReadonlyArray<TrendPoint>;
}

export interface Trends {
  readonly today: string;
  readonly query: TrendQuery;
  readonly from: string;
  readonly previousFrom: string;
  /** Whether Analytics Engine could be read; when not, everything is from D1. */
  readonly engine: "used" | "not-applicable" | "unavailable";
  readonly groups: ReadonlyArray<TrendGroup>;
  readonly experiments: ReadonlyArray<string>;
}

/** Most groups shown; the rest are added up as `other`. */
const maxGroups = 8;

const isClientEvent = (name: string) =>
  (ClientEventName.literals as ReadonlyArray<string>).includes(name);

export const engineCanAnswer = (query: TrendQuery): boolean =>
  isClientEvent(query.event) &&
  query.split !== "variant" &&
  (query.metric === "count" || (query.metric === "pairs" && query.interval === "day"));

interface Bucket {
  count: number;
  people: Set<string>;
  pairs: Set<string>;
  /** Pairs, or people for what happened before pairing: who a "too few" counts. */
  units: Set<string>;
}

const emptyBucket = (): Bucket => ({
  count: 0,
  people: new Set(),
  pairs: new Set(),
  units: new Set(),
});

const valueOf = (bucket: Bucket | undefined, metric: TrendMetric): number | null => {
  if (bucket === undefined || bucket.units.size < minimumGroup) return null;
  switch (metric) {
    case "count":
      return bucket.count;
    case "people":
      return bucket.people.size;
    case "pairs":
      return bucket.pairs.size;
    case "perPair":
      return bucket.pairs.size < minimumGroup ? null : bucket.count / bucket.pairs.size;
  }
};

export const buildTrends = (
  events: ReadonlyArray<BuildEventRow>,
  flags: ReadonlyArray<FlagRow>,
  today: string,
  query: TrendQuery,
  engine?: { readonly rows: ReadonlyArray<EngineRow> } | "unavailable",
): Trends => {
  const days = Number(query.range);
  const from = addDays(today, -days + 1);
  const previousFrom = addDays(from, -days);
  const startOf = (day: string) => (query.interval === "week" ? weekOf(day) : day);

  // A server-recorded row carries no build; take the person's build from their other rows that day.
  const buildOfDay = new Map<string, { appVersion: string | null; os: string | null }>();
  for (const row of events) {
    if (row.appVersion !== undefined && row.appVersion !== null) {
      buildOfDay.set(`${row.userId}|${row.day}`, {
        appVersion: row.appVersion,
        os: row.os ?? null,
      });
    }
  }
  const variantOf =
    query.split === "variant"
      ? new Map(
          flags
            .filter((flag) => flag.experimentKey === query.key)
            .map((flag) => [flag.pairId, flag.variant]),
        )
      : undefined;
  const groupOf = (row: BuildEventRow): string => {
    switch (query.split) {
      case "none":
        return "all";
      case "variant":
        return variantOf?.get(row.pairId) ?? "not in it";
      case "version":
        return (
          row.appVersion ?? buildOfDay.get(`${row.userId}|${row.day}`)?.appVersion ?? "unknown"
        );
      case "os":
        return row.os ?? buildOfDay.get(`${row.userId}|${row.day}`)?.os ?? "unknown";
    }
  };

  // Buckets per group and start, for both periods; and the same over each whole period.
  const buckets = new Map<string, Map<string, Bucket>>();
  const totals = new Map<string, { current: Bucket; previous: Bucket }>();
  for (const row of events) {
    if (row.name !== query.event || row.day < previousFrom || row.day > today) continue;
    const group = groupOf(row);
    const byStart = buckets.get(group) ?? new Map<string, Bucket>();
    const start = startOf(row.day);
    const bucket = byStart.get(start) ?? emptyBucket();
    const total = totals.get(group) ?? { current: emptyBucket(), previous: emptyBucket() };
    for (const target of [bucket, row.day >= from ? total.current : total.previous]) {
      target.count += row.count;
      target.people.add(row.userId);
      if (row.pairId !== "") target.pairs.add(row.pairId);
      target.units.add(row.pairId === "" ? `person:${row.userId}` : row.pairId);
    }
    byStart.set(start, bucket);
    buckets.set(group, byStart);
    totals.set(group, total);
  }

  const starts: Array<string> = [];
  for (let offset = 0; offset < days; offset += 1) {
    const start = startOf(addDays(from, offset));
    if (starts.at(-1) !== start) starts.push(start);
  }
  // The same point one period earlier, on its own week's Monday for weeks.
  const before = (start: string) => startOf(addDays(start, -days));

  // Analytics Engine's answer, when it applies: per group and start, summed over days for weeks.
  const canAnswer = engineCanAnswer(query);
  const engineFrom = addDays(today, -analyticsEngineDays + 1);
  const fromEngine = new Map<string, Map<string, { count: number; pairs: number }>>();
  if (canAnswer && engine !== undefined && engine !== "unavailable") {
    for (const row of engine.rows) {
      const group = query.split === "none" ? "all" : row.group === "" ? "unknown" : row.group;
      const byStart = fromEngine.get(group) ?? new Map<string, { count: number; pairs: number }>();
      const start = startOf(row.day);
      const point = byStart.get(start) ?? { count: 0, pairs: 0 };
      byStart.set(start, { count: point.count + row.count, pairs: point.pairs + row.pairs });
      fromEngine.set(group, byStart);
    }
  }
  const engineCovers = (start: string) =>
    canAnswer && engine !== undefined && engine !== "unavailable" && start >= engineFrom;
  const engineValue = (group: string, start: string): number | null => {
    const point = fromEngine.get(group)?.get(start);
    if (point === undefined || point.pairs < minimumGroup) return null;
    return query.metric === "count" ? Math.round(point.count) : point.pairs;
  };

  const pointOf = (group: string, start: string): TrendPoint => {
    const d1 = (at: string) => valueOf(buckets.get(group)?.get(at), query.metric);
    const useEngine = engineCovers(start);
    return {
      start,
      value: useEngine ? engineValue(group, start) : d1(start),
      previous: engineCovers(before(start)) ? engineValue(group, before(start)) : d1(before(start)),
      source: useEngine ? "analytics-engine" : "d1",
    };
  };

  const names = new Set([...totals.keys(), ...fromEngine.keys()]);
  const ranked = [...names].toSorted(
    (a, b) =>
      (totals.get(b)?.current.count ?? 0) - (totals.get(a)?.current.count ?? 0) ||
      a.localeCompare(b),
  );
  const shown = ranked.slice(0, maxGroups);
  const rest = ranked.slice(maxGroups);
  if (rest.length > 0) {
    const other = new Map<string, Bucket>();
    const otherTotal = { current: emptyBucket(), previous: emptyBucket() };
    const merge = (into: Bucket, from: Bucket) => {
      into.count += from.count;
      for (const key of ["people", "pairs", "units"] as const)
        for (const value of from[key]) into[key].add(value);
    };
    for (const group of rest) {
      for (const [start, bucket] of buckets.get(group) ?? []) {
        const target = other.get(start) ?? emptyBucket();
        merge(target, bucket);
        other.set(start, target);
      }
      const total = totals.get(group);
      if (total !== undefined) {
        merge(otherTotal.current, total.current);
        merge(otherTotal.previous, total.previous);
      }
      const engineRows = fromEngine.get(group);
      if (engineRows !== undefined) {
        const target =
          fromEngine.get("other") ?? new Map<string, { count: number; pairs: number }>();
        for (const [start, point] of engineRows) {
          const was = target.get(start) ?? { count: 0, pairs: 0 };
          target.set(start, { count: was.count + point.count, pairs: was.pairs + point.pairs });
        }
        fromEngine.set("other", target);
      }
    }
    buckets.set("other", other);
    totals.set("other", otherTotal);
    shown.push("other");
  }

  return {
    today,
    query,
    from,
    previousFrom,
    engine: !canAnswer
      ? "not-applicable"
      : engine === undefined || engine === "unavailable"
        ? "unavailable"
        : "used",
    groups: shown.map((group) => ({
      group,
      total: valueOf(totals.get(group)?.current, query.metric),
      previousTotal: valueOf(totals.get(group)?.previous, query.metric),
      points: starts.map((start) => pointOf(group, start)),
    })),
    experiments: [...new Set(flags.map(({ experimentKey }) => experimentKey))].toSorted(),
  };
};
