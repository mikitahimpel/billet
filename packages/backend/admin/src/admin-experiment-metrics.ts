import { addDays, type FlagRow, wilson } from "@billet/backend-metrics/funnel";
import { minimumGroup, type BuildEventRow } from "./admin-retention.ts";

/**
 * Secondary and guardrail metrics for each experiment, per variant, each with a 95% interval and
 * the difference from the baseline (the experiment's default variant) with its own interval.
 * Pure, from the same D1 rows as the north star.
 *
 * Every metric is read over a pair's first week, so a variant whose pairs are younger is not
 * judged on less time: only pairs at least 7 days old count, and day 0 is the day the pair formed.
 * A guardrail is worse when the whole interval of its difference sits on the wrong side of zero.
 */

export type MetricRole = "secondary" | "guardrail";
export type MetricUnit = "share" | "perDay";

/** A number with its 95% interval. */
export interface Estimate {
  readonly value: number;
  readonly low: number;
  readonly high: number;
}

/** `better` or `worse` only when the difference's interval leaves out zero. */
export type Change = "better" | "worse" | "unclear";

export interface VariantMetric {
  readonly variant: string;
  /** Pairs old enough to be measured. */
  readonly pairs: number;
  /** Null when `pairs` is below `minimumGroup` ("too few") or the metric is waiting. */
  readonly estimate: Estimate | null;
  /** Variant minus baseline; null for the baseline itself or when either side is too few. */
  readonly vsBaseline: Estimate | null;
  readonly change: Change | null;
}

export interface ExperimentMetric {
  readonly id: MetricId;
  readonly label: string;
  readonly description: string;
  readonly role: MetricRole;
  readonly unit: MetricUnit;
  /** `waiting` until the data exists; `waitingFor` says what it waits for. */
  readonly status: "ready" | "waiting";
  readonly waitingFor: string | null;
  readonly variants: ReadonlyArray<VariantMetric>;
}

export interface GuardrailWarning {
  readonly metric: MetricId;
  readonly variant: string;
  readonly text: string;
}

export interface ExperimentMetrics {
  readonly key: string;
  readonly baseline: string;
  readonly metrics: ReadonlyArray<ExperimentMetric>;
  readonly warnings: ReadonlyArray<GuardrailWarning>;
}

export type MetricId = "d7BothActive" | "widgetAdded" | "notesPerDay" | "opensPerDay" | "crashFree";

interface PairWeek {
  readonly pairId: string;
  readonly members: ReadonlyArray<string>;
  readonly formedDay: string;
  /** Rows of the pair from day 0 to day 7. */
  readonly rows: ReadonlyArray<BuildEventRow>;
}

interface Definition {
  readonly id: MetricId;
  readonly label: string;
  readonly description: string;
  readonly role: MetricRole;
  readonly unit: MetricUnit;
  readonly waitingFor?: string;
  /** For a share: did the pair do it. For a rate: its value. */
  readonly measure?: (pair: PairWeek) => boolean | number;
}

const usersOn = (pair: PairWeek, names: ReadonlyArray<string>, from: number, to: number) => {
  const first = addDays(pair.formedDay, from);
  const last = addDays(pair.formedDay, to);
  return new Set(
    pair.rows
      .filter(({ name, day }) => names.includes(name) && day >= first && day <= last)
      .map(({ userId }) => userId),
  );
};

const both = (pair: PairWeek, users: ReadonlySet<string>) =>
  pair.members.length === 2 && pair.members.every((member) => users.has(member));

const perDayOverWeek = (pair: PairWeek, name: string) => {
  const last = addDays(pair.formedDay, 6);
  let total = 0;
  for (const row of pair.rows) if (row.name === name && row.day <= last) total += row.count;
  return total / 7;
};

export const experimentMetricDefinitions: ReadonlyArray<Definition> = [
  {
    id: "d7BothActive",
    label: "D7 both active",
    description: "Both partners opened the app or sent a note on day 7",
    role: "secondary",
    unit: "share",
    measure: (pair) => both(pair, usersOn(pair, ["AppOpened", "NoteSent"], 7, 7)),
  },
  {
    id: "widgetAdded",
    label: "Widget added",
    description: "Both partners added the widget in the first week (days 0 to 6)",
    role: "secondary",
    unit: "share",
    measure: (pair) => both(pair, usersOn(pair, ["WidgetAdded"], 0, 6)),
  },
  {
    id: "notesPerDay",
    label: "Notes per pair per day",
    description: "Notes sent by the pair over days 0 to 6, divided by 7",
    role: "guardrail",
    unit: "perDay",
    measure: (pair) => perDayOverWeek(pair, "NoteSent"),
  },
  {
    id: "opensPerDay",
    label: "App opens per pair per day",
    description: "App opens by both partners over days 0 to 6, divided by 7",
    role: "guardrail",
    unit: "perDay",
    measure: (pair) => perDayOverWeek(pair, "AppOpened"),
  },
  {
    id: "crashFree",
    label: "Crash-free share",
    description: "Share of pairs with no crash in the first week",
    role: "guardrail",
    unit: "share",
    waitingFor: "#38 (crash monitoring)",
  },
];

const z = 1.96;

const shareEstimate = (count: number, of: number): Estimate => {
  const interval = wilson(count, of);
  return { value: count / of, low: interval?.low ?? 0, high: interval?.high ?? 1 };
};

/** Newcombe's hybrid score interval for the difference of two shares, from their Wilson ones. */
const shareDifference = (variant: Estimate, baseline: Estimate): Estimate => {
  const value = variant.value - baseline.value;
  return {
    value,
    low: value - Math.hypot(variant.value - variant.low, baseline.high - baseline.value),
    high: value + Math.hypot(variant.high - variant.value, baseline.value - baseline.low),
  };
};

interface MeanFacts {
  readonly mean: number;
  /** Squared standard error of the mean. */
  readonly se2: number;
}

const meanFacts = (values: ReadonlyArray<number>): MeanFacts => {
  const n = values.length;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const variance = values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / (n - 1);
  return { mean, se2: variance / n };
};

const meanEstimate = ({ mean, se2 }: MeanFacts): Estimate => ({
  value: mean,
  low: Math.max(0, mean - z * Math.sqrt(se2)),
  high: mean + z * Math.sqrt(se2),
});

/** Welch's interval (normal approximation) for the difference of two means. */
const meanDifference = (variant: MeanFacts, baseline: MeanFacts): Estimate => {
  const value = variant.mean - baseline.mean;
  const margin = z * Math.sqrt(variant.se2 + baseline.se2);
  return { value, low: value - margin, high: value + margin };
};

const changeOf = (difference: Estimate): Change =>
  difference.low > 0 ? "better" : difference.high < 0 ? "worse" : "unclear";

/** Each pair at least 7 days old, with its members and its rows from day 0 to day 7. */
export const pairWeeks = (
  events: ReadonlyArray<BuildEventRow>,
  today: string,
): ReadonlyMap<string, PairWeek> => {
  const byPair = new Map<string, Array<BuildEventRow>>();
  for (const row of events) {
    if (row.pairId === "") continue;
    const list = byPair.get(row.pairId) ?? [];
    list.push(row);
    byPair.set(row.pairId, list);
  }
  const weeks = new Map<string, PairWeek>();
  for (const [pairId, rows] of byPair) {
    const claims = rows.filter(({ name }) => name === "PairClaimed");
    const formedDay = claims.map(({ day }) => day).toSorted()[0];
    if (formedDay === undefined || addDays(formedDay, 7) > today) continue;
    const last = addDays(formedDay, 7);
    weeks.set(pairId, {
      pairId,
      members: [...new Set(claims.map(({ userId }) => userId))],
      formedDay,
      rows: rows.filter(({ day }) => day >= formedDay && day <= last),
    });
  }
  return weeks;
};

/** Signed, with a real minus sign, as the page shows it. */
const fmt = (definition: Definition, value: number) => {
  const sign = value < 0 ? "−" : value > 0 ? "+" : "";
  const size = Math.abs(value);
  return `${sign}${definition.unit === "share" ? `${(size * 100).toFixed(1)} points` : size.toFixed(2)}`;
};

const warningText = (definition: Definition, variant: string, baseline: string, d: Estimate) =>
  `${definition.label} is worse in ${variant} than in ${baseline}: ${fmt(definition, d.value)} (95% ${fmt(definition, d.low)} to ${fmt(definition, d.high)}).`;

const metricFor = (
  definition: Definition,
  groups: ReadonlyArray<readonly [string, ReadonlyArray<PairWeek>]>,
  baseline: string,
): ExperimentMetric => {
  const measure = definition.measure;
  const shared = {
    id: definition.id,
    label: definition.label,
    description: definition.description,
    role: definition.role,
    unit: definition.unit,
  };
  if (measure === undefined) {
    return {
      ...shared,
      status: "waiting",
      waitingFor: definition.waitingFor ?? null,
      variants: groups.map(([variant, pairs]) => ({
        variant,
        pairs: pairs.length,
        estimate: null,
        vsBaseline: null,
        change: null,
      })),
    };
  }
  type Facts = { readonly share: Estimate } | { readonly mean: MeanFacts } | null;
  const facts = new Map<string, Facts>(
    groups.map(([variant, pairs]): readonly [string, Facts] => {
      if (pairs.length < minimumGroup) return [variant, null] as const;
      const values = pairs.map(measure);
      if (definition.unit === "share") {
        const count = values.filter((value) => value === true).length;
        return [variant, { share: shareEstimate(count, pairs.length) }] as const;
      }
      return [variant, { mean: meanFacts(values.map(Number)) }] as const;
    }),
  );
  const base = facts.get(baseline) ?? null;
  return {
    ...shared,
    status: "ready",
    waitingFor: null,
    variants: groups.map(([variant, pairs]) => {
      const own = facts.get(variant) ?? null;
      const estimate = own === null ? null : "share" in own ? own.share : meanEstimate(own.mean);
      const vsBaseline =
        own === null || base === null || variant === baseline
          ? null
          : "share" in own && "share" in base
            ? shareDifference(own.share, base.share)
            : "mean" in own && "mean" in base
              ? meanDifference(own.mean, base.mean)
              : null;
      return {
        variant,
        pairs: pairs.length,
        estimate,
        vsBaseline,
        change: vsBaseline === null ? null : changeOf(vsBaseline),
      };
    }),
  };
};

/**
 * For each experiment in `flags`, the metrics above per variant. `baselines` maps a key to its
 * default variant; without one (or when no pair has it), the first variant by name is the baseline.
 */
export const buildExperimentMetrics = (
  events: ReadonlyArray<BuildEventRow>,
  flags: ReadonlyArray<FlagRow>,
  today: string,
  baselines: ReadonlyMap<string, string> = new Map(),
): ReadonlyArray<ExperimentMetrics> => {
  const weeks = pairWeeks(events, today);
  const variantsByKey = new Map<string, Map<string, Array<PairWeek>>>();
  for (const flag of flags) {
    const variants = variantsByKey.get(flag.experimentKey) ?? new Map<string, Array<PairWeek>>();
    const list = variants.get(flag.variant) ?? [];
    const week = weeks.get(flag.pairId);
    if (week !== undefined) list.push(week);
    variants.set(flag.variant, list);
    variantsByKey.set(flag.experimentKey, variants);
  }
  return [...variantsByKey]
    .toSorted(([a], [b]) => a.localeCompare(b))
    .map(([key, variants]) => {
      const groups = [...variants].toSorted(([a], [b]) => a.localeCompare(b));
      const wanted = baselines.get(key);
      const baseline =
        wanted !== undefined && variants.has(wanted) ? wanted : (groups[0]?.[0] ?? "");
      const metrics = experimentMetricDefinitions.map((definition) =>
        metricFor(definition, groups, baseline),
      );
      const warnings = metrics.flatMap((metric) => {
        const definition = experimentMetricDefinitions.find(({ id }) => id === metric.id);
        if (definition === undefined || metric.role !== "guardrail") return [];
        return metric.variants.flatMap((variant) =>
          variant.change === "worse" && variant.vsBaseline !== null
            ? [
                {
                  metric: metric.id,
                  variant: variant.variant,
                  text: warningText(definition, variant.variant, baseline, variant.vsBaseline),
                },
              ]
            : [],
        );
      });
      return { key, baseline, metrics, warnings };
    });
};
