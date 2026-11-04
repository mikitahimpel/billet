import {
  addDays,
  buildReport,
  type EventRow,
  type FlagRow,
  share,
  type Share,
} from "@billet/backend-metrics/funnel";

export interface DailyPoint {
  readonly day: string;
  /** People who opened the app or sent a note that day. */
  readonly dau: number;
  /** The same over the 7 days ending that day. */
  readonly wau: number;
  /** Pairs whose first `PairClaimed` fell on that day. */
  readonly pairsCreated: number;
  readonly notes: number;
}

/** A count over the chosen range, the same over the range before it, and its daily values. */
export interface Stat {
  readonly current: number | null;
  readonly previous: number | null;
  /** One value per day of the current range, oldest first; `null` where there is nothing to divide. */
  readonly series: ReadonlyArray<number | null>;
}

/** A share over the chosen range against the range before it. */
export interface ShareStat {
  readonly current: Share;
  readonly previous: Share;
}

/** The ranges the panel offers. Anything else is read as 30. */
export const overviewRanges = [7, 30, 90] as const;
export type OverviewRange = (typeof overviewRanges)[number];

export const rangeOf = (value: number | undefined): OverviewRange =>
  overviewRanges.find((range) => range === value) ?? 30;

export type FunnelStep = "install" | "signedIn" | "paired" | "firstNote" | "secondDay";

export interface Overview {
  readonly today: string;
  /** The current range (`from`..`to`, inclusive) and the one just before it, as UTC days. */
  readonly range: {
    readonly days: OverviewRange;
    readonly from: string;
    readonly to: string;
    readonly previousFrom: string;
    readonly previousTo: string;
  };
  /**
   * The stat cards, each over the range and the range before it. DAU is the mean per day, WAU is
   * on the range's last day, new pairs are summed, notes per pair per day divide the notes by the
   * days each pair existed. Pair completion and D1/D7 are cohorts: inviters whose first invite, and
   * pairs that formed, fell in the range.
   */
  readonly stats: {
    readonly dau: Stat;
    readonly wau: Stat;
    readonly newPairs: Stat;
    readonly notesPerPairPerDay: Stat;
    readonly pairCompletion: ShareStat;
    readonly d1: ShareStat;
    readonly d7: ShareStat;
  };
  readonly totals: { readonly users: number; readonly pairs: number; readonly notes: number };
  readonly daily: ReadonlyArray<DailyPoint>;
  readonly funnel: ReadonlyArray<{
    readonly step: FunnelStep;
    readonly label: string;
    readonly count: number | null;
    readonly note?: string;
  }>;
  readonly pairCompletion: Share;
  readonly notesPerPairPerDay: { readonly pairs: number; readonly mean: number | null };
  readonly retention: ReadonlyArray<{
    readonly day: number;
    readonly eligible: number;
    readonly bothActive: Share;
    readonly bothSentNote: Share;
  }>;
}

const active = (row: EventRow) => row.name === "AppOpened" || row.name === "NoteSent";

const mean = (values: ReadonlyArray<number>): number | null =>
  values.length === 0 ? null : values.reduce((a, b) => a + b, 0) / values.length;

const sum = (values: ReadonlyArray<number>) => values.reduce((a, b) => a + b, 0);

/**
 * The Overview page, from the D1 counts. Pure, like `buildReport`, which it reuses for the pair
 * figures. DAU and WAU count people; a day is a UTC day. `days` is the range the stat cards and
 * charts cover (7, 30 or 90); the funnel and the totals are all time.
 */
export const buildOverview = (
  events: ReadonlyArray<EventRow>,
  flags: ReadonlyArray<FlagRow>,
  userCount: number,
  today: string,
  days: number = 30,
): Overview => {
  const range = rangeOf(days);
  const report = buildReport(events, flags, today);

  const activeByDay = new Map<string, Set<string>>();
  const daysByUser = new Map<string, Set<string>>();
  const notesByDay = new Map<string, number>();
  const pairStart = new Map<string, string>();
  for (const row of events) {
    if (active(row)) {
      const users = activeByDay.get(row.day) ?? new Set<string>();
      users.add(row.userId);
      activeByDay.set(row.day, users);
    }
    const seen = daysByUser.get(row.userId) ?? new Set<string>();
    seen.add(row.day);
    daysByUser.set(row.userId, seen);
    if (row.name === "NoteSent")
      notesByDay.set(row.day, (notesByDay.get(row.day) ?? 0) + row.count);
    if (row.name === "PairClaimed" && row.pairId !== "") {
      const first = pairStart.get(row.pairId);
      if (first === undefined || row.day < first) pairStart.set(row.pairId, row.day);
    }
  }
  const pairsByDay = new Map<string, number>();
  for (const day of pairStart.values()) pairsByDay.set(day, (pairsByDay.get(day) ?? 0) + 1);

  const firstInvite = new Map<string, string>();
  for (const row of events) {
    if (row.name !== "InviteCreated") continue;
    const first = firstInvite.get(row.userId);
    if (first === undefined || row.day < first) firstInvite.set(row.userId, row.day);
  }
  const pairedUsers = new Set(
    events.filter((row) => row.name === "PairClaimed").map(({ userId }) => userId),
  );

  // Both ranges, oldest first: the previous range, then the current one ending today.
  const both = Array.from({ length: range * 2 }, (_, index): DailyPoint => {
    const day = addDays(today, index - range * 2 + 1);
    const week = new Set<string>();
    for (let back = 0; back < 7; back += 1) {
      for (const user of activeByDay.get(addDays(day, -back)) ?? []) week.add(user);
    }
    return {
      day,
      dau: activeByDay.get(day)?.size ?? 0,
      wau: week.size,
      pairsCreated: pairsByDay.get(day) ?? 0,
      notes: notesByDay.get(day) ?? 0,
    };
  });
  const previousDaily = both.slice(0, range);
  const daily = both.slice(range);

  const pairsOn = (day: string) => [...pairStart.values()].filter((start) => start <= day).length;
  const notesPerPair = (points: ReadonlyArray<DailyPoint>) => {
    const pairDays = sum(points.map(({ day }) => pairsOn(day)));
    return pairDays === 0 ? null : sum(points.map(({ notes }) => notes)) / pairDays;
  };

  const inRange = (day: string, from: string, to: string) => day >= from && day <= to;
  const completion = (from: string, to: string) => {
    const cohort = [...firstInvite].filter(([, day]) => inRange(day, from, to));
    return share(cohort.filter(([user]) => pairedUsers.has(user)).length, cohort.length);
  };
  const retention = (from: string, to: string) => {
    const cohort = new Set(
      [...pairStart].filter(([, day]) => inRange(day, from, to)).map(([pairId]) => pairId),
    );
    const { days: activity } = buildReport(
      events.filter((row) => cohort.has(row.pairId)),
      [],
      today,
    );
    const on = (n: number) => activity.find(({ day }) => day === n)?.bothActive ?? share(0, 0);
    return { d1: on(1), d7: on(7) };
  };

  const from = daily[0]?.day ?? today;
  const previousFrom = previousDaily[0]?.day ?? today;
  const previousTo = previousDaily.at(-1)?.day ?? today;
  const current = retention(from, today);
  const previous = retention(previousFrom, previousTo);

  const usersWith = (name: EventRow["name"]) =>
    new Set(events.filter((row) => row.name === name).map(({ userId }) => userId)).size;

  return {
    today,
    range: { days: range, from, to: today, previousFrom, previousTo },
    stats: {
      dau: {
        current: mean(daily.map(({ dau }) => dau)),
        previous: mean(previousDaily.map(({ dau }) => dau)),
        series: daily.map(({ dau }) => dau),
      },
      wau: {
        current: daily.at(-1)?.wau ?? null,
        previous: previousDaily.at(-1)?.wau ?? null,
        series: daily.map(({ wau }) => wau),
      },
      newPairs: {
        current: sum(daily.map(({ pairsCreated }) => pairsCreated)),
        previous: sum(previousDaily.map(({ pairsCreated }) => pairsCreated)),
        series: daily.map(({ pairsCreated }) => pairsCreated),
      },
      notesPerPairPerDay: {
        current: notesPerPair(daily),
        previous: notesPerPair(previousDaily),
        series: daily.map((point) => notesPerPair([point])),
      },
      pairCompletion: {
        current: completion(from, today),
        previous: completion(previousFrom, previousTo),
      },
      d1: { current: current.d1, previous: previous.d1 },
      d7: { current: current.d7, previous: previous.d7 },
    },
    totals: {
      users: userCount,
      pairs: report.pairsFormed,
      notes: [...notesByDay.values()].reduce((a, b) => a + b, 0),
    },
    daily,
    funnel: [
      {
        step: "install",
        label: "Installed",
        count: null,
        note: "App Store Connect counts installs; the app reports nothing before sign-in.",
      },
      { step: "signedIn", label: "Signed in", count: userCount },
      { step: "paired", label: "Paired", count: usersWith("PairClaimed") },
      { step: "firstNote", label: "Sent a first note", count: usersWith("NoteSent") },
      {
        step: "secondDay",
        label: "Came back a second day",
        count: [...daysByUser.values()].filter((seen) => seen.size >= 2).length,
      },
    ],
    pairCompletion: report.inviterPaired,
    notesPerPairPerDay: {
      pairs: report.notesPerPairPerDay.pairs,
      mean: report.notesPerPairPerDay.mean ?? null,
    },
    retention: report.days.map(({ day, eligible, bothActive, bothSentNote }) => ({
      day,
      eligible,
      bothActive,
      bothSentNote,
    })),
  };
};
