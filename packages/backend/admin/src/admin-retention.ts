import { addDays, type EventRow, type FlagRow, wilson } from "@billet/backend-metrics/funnel";

/**
 * The retention grid: one row per week in which pairs formed, one column per day after forming.
 * Pure, from the same D1 rows as the Overview. A day is a UTC day and day 0 is the day the pair
 * formed, as in the owner report (`buildReport`).
 */

/** The days after forming the grid shows. */
export const retentionDays = [1, 3, 7, 14, 30, 60] as const;

/** Below this many pairs a cell says "too few" and carries no number at all. */
export const minimumGroup = 5;

/** A `pair_events` row with the build that sent it, when the server knew it. */
export interface BuildEventRow extends EventRow {
  /** The day's last moment; the funnel uses it. Taken as `firstAt` when absent. */
  readonly lastAt?: number;
  /** `x-billet-app-version` as `<marketing>+<build>`, or null when it was not recorded. */
  readonly appVersion?: string | null;
  /** `x-billet-os`, such as `iOS 26.1`, or null. */
  readonly os?: string | null;
}

/**
 * - `both`: both partners active (opened the app or sent a note) on day N;
 * - `either`: at least one of them active;
 * - `bothNote`: both sent a note on day N, the north star at day 7.
 */
export type RetentionMode = "both" | "either" | "bothNote";
export const retentionModes: ReadonlyArray<RetentionMode> = ["both", "either", "bothNote"];

/**
 * One cell. `pending`: no pair of the week has reached the day yet (greyed). `too-few`: fewer than
 * `minimumGroup` have, and nothing else is said. Otherwise the share of the pairs that have
 * reached it, with its 95% Wilson interval; `partial` when some of the week's pairs are still too
 * young to count.
 */
export type RetentionCell =
  | { readonly state: "pending" }
  | { readonly state: "too-few" }
  | {
      readonly state: "value";
      readonly count: number;
      readonly of: number;
      readonly share: number;
      readonly low: number;
      readonly high: number;
      readonly partial: boolean;
    };

export interface RetentionRow {
  /** The Monday (UTC) that starts the week, or `all` for every week together. */
  readonly week: string;
  /** Pairs formed that week, or null when fewer than `minimumGroup`. */
  readonly pairs: number | null;
  /** One entry per `retentionDays`, in that order, per mode. */
  readonly cells: { readonly [Mode in RetentionMode]: ReadonlyArray<RetentionCell> };
}

export interface RetentionFilter {
  /** `key=variant`: only pairs stored in that variant. */
  readonly variant?: { readonly key: string; readonly variant: string } | undefined;
  /** Only pairs on this build (`1.2.0+14`) when they formed (see `pairsOf`), or `unknown`. */
  readonly appVersion?: string | undefined;
}

export interface RetentionGrid {
  readonly today: string;
  readonly days: ReadonlyArray<number>;
  readonly filter: { readonly variant: string | null; readonly appVersion: string | null };
  /** Newest week first, then `all`. */
  readonly rows: ReadonlyArray<RetentionRow>;
  /** What the filters can be set to, from the data. */
  readonly options: {
    readonly variants: ReadonlyArray<{ readonly key: string; readonly variant: string }>;
    readonly appVersions: ReadonlyArray<string>;
  };
}

/** The Monday on or before a UTC day. */
export const weekOf = (day: string): string => {
  const weekday = new Date(`${day}T00:00:00Z`).getUTCDay();
  return addDays(day, -((weekday + 6) % 7));
};

interface Pair {
  readonly pairId: string;
  readonly members: ReadonlyArray<string>;
  readonly formedDay: string;
  readonly appVersion: string;
  /** Day to the members active (opened or sent a note) on it. */
  readonly active: ReadonlyMap<string, ReadonlySet<string>>;
  /** Day to the members who sent a note on it. */
  readonly noted: ReadonlyMap<string, ReadonlySet<string>>;
}

const add = (map: Map<string, Set<string>>, day: string, user: string) => {
  const set = map.get(day) ?? new Set<string>();
  set.add(user);
  map.set(day, set);
};

/**
 * The pairs in the rows: members are those with a `PairClaimed` row and the pair formed on the
 * earliest of those days. Its build is the one on its earliest row the app sent (the server's own
 * rows, such as the claim, carry none): the build it paired on. `unknown` when it has none.
 */
export const pairsOf = (events: ReadonlyArray<BuildEventRow>): ReadonlyArray<Pair> => {
  const byPair = new Map<string, Array<BuildEventRow>>();
  for (const row of events) {
    if (row.pairId === "") continue;
    const list = byPair.get(row.pairId) ?? [];
    list.push(row);
    byPair.set(row.pairId, list);
  }
  const pairs: Array<Pair> = [];
  for (const [pairId, rows] of byPair) {
    const claims = rows
      .filter(({ name }) => name === "PairClaimed")
      .toSorted((a, b) => a.firstAt - b.firstAt);
    const firstClaim = claims[0];
    if (firstClaim === undefined) continue;
    const active = new Map<string, Set<string>>();
    const noted = new Map<string, Set<string>>();
    for (const row of rows) {
      if (row.name === "AppOpened" || row.name === "NoteSent") add(active, row.day, row.userId);
      if (row.name === "NoteSent") add(noted, row.day, row.userId);
    }
    pairs.push({
      pairId,
      members: [...new Set(claims.map(({ userId }) => userId))],
      formedDay: claims.map(({ day }) => day).toSorted()[0] ?? firstClaim.day,
      appVersion:
        rows
          .filter((row) => row.appVersion !== undefined && row.appVersion !== null)
          .toSorted((a, b) => a.firstAt - b.firstAt || a.userId.localeCompare(b.userId))[0]
          ?.appVersion ?? "unknown",
      active,
      noted,
    });
  }
  return pairs;
};

const holds = (pair: Pair, mode: RetentionMode, day: string): boolean => {
  const present = (mode === "bothNote" ? pair.noted : pair.active).get(day);
  if (present === undefined) return false;
  if (mode === "either") return pair.members.some((member) => present.has(member));
  return pair.members.length === 2 && pair.members.every((member) => present.has(member));
};

const cellOf = (
  pairs: ReadonlyArray<Pair>,
  mode: RetentionMode,
  n: number,
  today: string,
): RetentionCell => {
  const reached = pairs.filter((pair) => addDays(pair.formedDay, n) <= today);
  if (reached.length === 0) return { state: "pending" };
  if (reached.length < minimumGroup) return { state: "too-few" };
  const count = reached.filter((pair) => holds(pair, mode, addDays(pair.formedDay, n))).length;
  const interval = wilson(count, reached.length);
  return {
    state: "value",
    count,
    of: reached.length,
    share: count / reached.length,
    low: interval?.low ?? 0,
    high: interval?.high ?? 1,
    partial: reached.length < pairs.length,
  };
};

const rowOf = (week: string, pairs: ReadonlyArray<Pair>, today: string): RetentionRow => {
  const cells = (mode: RetentionMode) => retentionDays.map((n) => cellOf(pairs, mode, n, today));
  return {
    week,
    pairs: pairs.length < minimumGroup ? null : pairs.length,
    cells: { both: cells("both"), either: cells("either"), bothNote: cells("bothNote") },
  };
};

export const buildRetentionGrid = (
  events: ReadonlyArray<BuildEventRow>,
  flags: ReadonlyArray<FlagRow>,
  today: string,
  filter: RetentionFilter = {},
): RetentionGrid => {
  const all = pairsOf(events).filter((pair) => pair.formedDay <= today);
  const wanted = filter.variant;
  const inVariant =
    wanted === undefined
      ? undefined
      : new Set(
          flags
            .filter((flag) => flag.experimentKey === wanted.key && flag.variant === wanted.variant)
            .map(({ pairId }) => pairId),
        );
  const pairs = all.filter(
    (pair) =>
      (inVariant === undefined || inVariant.has(pair.pairId)) &&
      (filter.appVersion === undefined || pair.appVersion === filter.appVersion),
  );

  const byWeek = new Map<string, Array<Pair>>();
  for (const pair of pairs) {
    const week = weekOf(pair.formedDay);
    const list = byWeek.get(week) ?? [];
    list.push(pair);
    byWeek.set(week, list);
  }

  const known = new Set(all.map(({ pairId }) => pairId));
  const variants = new Map<string, { key: string; variant: string }>();
  for (const flag of flags) {
    if (!known.has(flag.pairId)) continue;
    variants.set(`${flag.experimentKey}=${flag.variant}`, {
      key: flag.experimentKey,
      variant: flag.variant,
    });
  }

  return {
    today,
    days: retentionDays,
    filter: {
      variant: wanted === undefined ? null : `${wanted.key}=${wanted.variant}`,
      appVersion: filter.appVersion ?? null,
    },
    rows: [
      ...[...byWeek]
        .toSorted(([a], [b]) => b.localeCompare(a))
        .map(([week, list]) => rowOf(week, list, today)),
      rowOf("all", pairs, today),
    ],
    options: {
      variants: [...variants].toSorted(([a], [b]) => a.localeCompare(b)).map(([, value]) => value),
      appVersions: [...new Set(all.map(({ appVersion }) => appVersion))].toSorted(),
    },
  };
};
