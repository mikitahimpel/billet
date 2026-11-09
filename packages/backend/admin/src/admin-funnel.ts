import { Schema } from "effect";
import { ClientEventName, ServerEventName } from "@billet/contracts-domain/metrics";
import { addDays, type FlagRow, wilson } from "@billet/backend-metrics/funnel";
import { minimumGroup, type BuildEventRow } from "./admin-retention.ts";

/**
 * Rows keep only a day's first and last moment, so a step may be placed late, never early.
 */

/** Every name `pair_events` can hold. `AccountDeleted` goes to Analytics Engine only. */
export const funnelEventNames: ReadonlyArray<string> = [
  ...ServerEventName.literals.filter((name) => name !== "AccountDeleted"),
  ...ClientEventName.literals,
];

export const FunnelWindow = Schema.Literals(["day", "1d", "7d"]);
export type FunnelWindow = typeof FunnelWindow.Type;

export const FunnelUnit = Schema.Literals(["pair", "person"]);
export type FunnelUnit = typeof FunnelUnit.Type;

export const FunnelRange = Schema.Literals(["7", "30", "90", "all"]);
export type FunnelRange = typeof FunnelRange.Type;

const StepName = Schema.String.check(
  Schema.makeFilter((name) => funnelEventNames.includes(name) || `${name} is not an event`),
);

export const FunnelDefinition = Schema.Struct({
  steps: Schema.Array(StepName).check(
    Schema.makeFilter(
      (steps) =>
        (steps.length >= 2 && steps.length <= 6 && new Set(steps).size === steps.length) ||
        "a funnel has 2 to 6 different steps",
    ),
  ),
  window: FunnelWindow,
  unit: FunnelUnit,
});
export type FunnelDefinition = typeof FunnelDefinition.Type;

/** A count, or null when it rests on fewer than `minimumGroup` pairs or people. */
export interface FunnelStep {
  readonly name: string;
  readonly count: number | null;
  /** Share of the step before that reached this one, with its 95% interval. Null when hidden. */
  readonly fromPrevious: {
    readonly share: number;
    readonly low: number;
    readonly high: number;
  } | null;
  readonly fromFirst: number | null;
  /** Median milliseconds from the step before, over those who reached this one. */
  readonly medianFromPrevious: number | null;
}

export interface FunnelGroup {
  /** The variant, or null for everyone. */
  readonly variant: string | null;
  /** Pairs or people who did step 1 in the range; null when fewer than `minimumGroup`. */
  readonly entered: number | null;
  readonly steps: ReadonlyArray<FunnelStep>;
}

export interface FunnelResult {
  readonly today: string;
  readonly definition: FunnelDefinition;
  readonly range: FunnelRange;
  /** The first day step 1 may fall on, or null for all time. */
  readonly from: string | null;
  readonly split: string | null;
  /** Everyone first, then each variant of `split` in order. */
  readonly groups: ReadonlyArray<FunnelGroup>;
  /** Experiment keys present in `pair_flags`, for the split picker. */
  readonly experiments: ReadonlyArray<string>;
}

const dayMillis = 86_400_000;

interface Occurrence {
  readonly firstAt: number;
  readonly lastAt: number;
  readonly day: string;
}

/** The first moment a step happened at or after `after`, as far as the day rows can tell. */
const firstFrom = (rows: ReadonlyArray<Occurrence>, after: number): number | undefined => {
  let best: number | undefined;
  for (const row of rows) {
    const at = row.firstAt >= after ? row.firstAt : row.lastAt >= after ? row.lastAt : undefined;
    if (at !== undefined && (best === undefined || at < best)) best = at;
  }
  return best;
};

const deadlineOf = (window: FunnelWindow, start: number): number =>
  window === "day"
    ? Math.floor(start / dayMillis) * dayMillis + dayMillis - 1
    : start + (window === "1d" ? 1 : 7) * dayMillis;

const median = (values: ReadonlyArray<number>): number | null => {
  if (values.length === 0) return null;
  const sorted = values.toSorted((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1
    ? (sorted[middle] ?? null)
    : ((sorted[middle - 1] ?? 0) + (sorted[middle] ?? 0)) / 2;
};

/** A unit is a pair (its rows after pairing) or a person (all their rows). */
export const funnelTimes = (
  events: ReadonlyArray<BuildEventRow>,
  definition: FunnelDefinition,
  from: string | null,
  today: string,
): ReadonlyMap<string, ReadonlyArray<number>> => {
  const wanted = new Set(definition.steps);
  const byUnit = new Map<string, Map<string, Array<Occurrence>>>();
  for (const row of events) {
    if (!wanted.has(row.name)) continue;
    const unit = definition.unit === "pair" ? row.pairId : row.userId;
    if (unit === "") continue;
    const names = byUnit.get(unit) ?? new Map<string, Array<Occurrence>>();
    const list = names.get(row.name) ?? [];
    list.push({ firstAt: row.firstAt, lastAt: row.lastAt ?? row.firstAt, day: row.day });
    names.set(row.name, list);
    byUnit.set(unit, names);
  }
  const times = new Map<string, ReadonlyArray<number>>();
  const [first, ...rest] = definition.steps;
  for (const [unit, names] of byUnit) {
    const entries = (names.get(first ?? "") ?? []).filter(
      ({ day }) => (from === null || day >= from) && day <= today,
    );
    if (entries.length === 0) continue;
    const start = Math.min(...entries.map(({ firstAt }) => firstAt));
    const deadline = deadlineOf(definition.window, start);
    const reached = [start];
    let previous = start;
    for (const step of rest) {
      const at = firstFrom(names.get(step) ?? [], previous);
      if (at === undefined || at > deadline) break;
      reached.push(at);
      previous = at;
    }
    times.set(unit, reached);
  }
  return times;
};

const hidden = (count: number) => count < minimumGroup;

const groupOf = (
  variant: string | null,
  definition: FunnelDefinition,
  times: ReadonlyArray<ReadonlyArray<number>>,
): FunnelGroup => {
  const entered = times.length;
  const steps = definition.steps.map((name, index): FunnelStep => {
    const reached = times.filter((list) => list.length > index);
    const count = reached.length;
    const before = index === 0 ? entered : times.filter((list) => list.length > index - 1).length;
    if (hidden(count) || hidden(before)) {
      return { name, count: null, fromPrevious: null, fromFirst: null, medianFromPrevious: null };
    }
    const interval = wilson(count, before);
    return {
      name,
      count,
      fromPrevious:
        index === 0
          ? null
          : { share: count / before, low: interval?.low ?? 0, high: interval?.high ?? 1 },
      fromFirst: index === 0 ? null : count / entered,
      medianFromPrevious:
        index === 0
          ? null
          : median(reached.map((list) => (list[index] ?? 0) - (list[index - 1] ?? 0))),
    };
  });
  return { variant, entered: hidden(entered) ? null : entered, steps };
};

/** The pair each person was in, from their `PairClaimed` rows (the earliest). */
const pairOfPerson = (events: ReadonlyArray<BuildEventRow>): ReadonlyMap<string, string> => {
  const claims = events
    .filter(({ name, pairId }) => name === "PairClaimed" && pairId !== "")
    .toSorted((a, b) => a.firstAt - b.firstAt);
  const pairs = new Map<string, string>();
  for (const claim of claims) if (!pairs.has(claim.userId)) pairs.set(claim.userId, claim.pairId);
  return pairs;
};

export const buildFunnel = (
  events: ReadonlyArray<BuildEventRow>,
  flags: ReadonlyArray<FlagRow>,
  today: string,
  definition: FunnelDefinition,
  options: { readonly range?: FunnelRange | undefined; readonly split?: string | undefined } = {},
): FunnelResult => {
  const range = options.range ?? "90";
  const from = range === "all" ? null : addDays(today, -Number(range) + 1);
  const times = funnelTimes(events, definition, from, today);
  const all = groupOf(null, definition, [...times.values()]);

  const split = options.split;
  const groups: Array<FunnelGroup> = [all];
  if (split !== undefined) {
    const variantOfPair = new Map(
      flags
        .filter((flag) => flag.experimentKey === split)
        .map((flag) => [flag.pairId, flag.variant]),
    );
    const pairs = definition.unit === "person" ? pairOfPerson(events) : undefined;
    const byVariant = new Map<string, Array<ReadonlyArray<number>>>();
    for (const [unit, list] of times) {
      const pairId = pairs === undefined ? unit : pairs.get(unit);
      const variant = pairId === undefined ? undefined : variantOfPair.get(pairId);
      if (variant === undefined) continue;
      const bucket = byVariant.get(variant) ?? [];
      bucket.push(list);
      byVariant.set(variant, bucket);
    }
    for (const variant of [...new Set(variantOfPair.values())].toSorted()) {
      groups.push(groupOf(variant, definition, byVariant.get(variant) ?? []));
    }
  }

  return {
    today,
    definition,
    range,
    from,
    split: split ?? null,
    groups,
    experiments: [...new Set(flags.map(({ experimentKey }) => experimentKey))].toSorted(),
  };
};
