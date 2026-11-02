import type { MetricEventName } from "@billet/contracts-domain/metrics";

/** A `pair_events` row, as the report reads it. */
export interface EventRow {
  readonly pairId: string;
  readonly userId: string;
  readonly name: MetricEventName;
  readonly day: string;
  readonly count: number;
  readonly firstAt: number;
}

/** A `pair_flags` row. */
export interface FlagRow {
  readonly pairId: string;
  readonly experimentKey: string;
  readonly variant: string;
}

export interface Interval {
  readonly low: number;
  readonly high: number;
}

/** A share with how many pairs it rests on, so a reader sees how little a small number says. */
export interface Share {
  readonly of: number;
  readonly count: number;
  readonly share: number | undefined;
  /** 95% Wilson interval. Absent when `of` is 0. */
  readonly interval: Interval | undefined;
}

export interface DayActivity {
  /** Days after the day the pair formed: 1, 7, 30. */
  readonly day: number;
  /** Pairs old enough to have a day N, which is all that can be measured. */
  readonly eligible: number;
  /** Both partners sent a note on that day. The north-star metric at day 7. */
  readonly bothSentNote: Share;
  /** Both partners sent a note or opened the app on that day. */
  readonly bothActive: Share;
}

export interface FunnelReport {
  /** UTC day the report was made for. */
  readonly today: string;
  readonly invitesCreated: number;
  readonly pairsFormed: number;
  /** Share of people who made an invite and are now in a pair. */
  readonly inviterPaired: Share;
  readonly widgetAddedByBoth: Share;
  readonly firstNoteBothWays: Share;
  /** Milliseconds from the pair forming to its first note, from either partner. */
  readonly medianToFirstNote: number | undefined;
  /** Milliseconds from the pair forming until both had sent a note. */
  readonly medianToFirstNoteBothWays: number | undefined;
  readonly days: ReadonlyArray<DayActivity>;
  /** Notes per pair per day over a pair's first 7 days, for pairs at least 7 days old. */
  readonly notesPerPairPerDay: { readonly pairs: number; readonly mean: number | undefined };
  readonly opening: { readonly watched: number; readonly skipped: number };
  readonly daily: ReadonlyArray<{
    readonly day: string;
    readonly notes: number;
    readonly pairsWithNote: number;
  }>;
  readonly experiments: ReadonlyArray<ExperimentReport>;
}

export interface VariantReport {
  readonly variant: string;
  readonly pairs: number;
  /** North star: both partners sent a note on day 7. Counts only pairs that have reached day 7. */
  readonly northStar: Share;
  readonly medianToFirstNote: number | undefined;
}

export interface ExperimentReport {
  readonly key: string;
  readonly variants: ReadonlyArray<VariantReport>;
  /** Plain words about whether the numbers can say anything yet. */
  readonly caution: string;
}

const dayNumber = (day: string): number => Math.floor(Date.parse(`${day}T00:00:00Z`) / 86_400_000);

export const addDays = (day: string, days: number): string =>
  new Date((dayNumber(day) + days) * 86_400_000).toISOString().slice(0, 10);

/** 95% Wilson score interval: honest at the small counts this app will have for a long time. */
export const wilson = (count: number, of: number): Interval | undefined => {
  if (of === 0) return undefined;
  const z = 1.96;
  const p = count / of;
  const denominator = 1 + (z * z) / of;
  const centre = (p + (z * z) / (2 * of)) / denominator;
  const margin = (z * Math.sqrt((p * (1 - p)) / of + (z * z) / (4 * of * of))) / denominator;
  return { low: Math.max(0, centre - margin), high: Math.min(1, centre + margin) };
};

export const share = (count: number, of: number): Share => ({
  of,
  count,
  share: of === 0 ? undefined : count / of,
  interval: wilson(count, of),
});

const median = (values: ReadonlyArray<number>): number | undefined => {
  if (values.length === 0) return undefined;
  const sorted = values.toSorted((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1
    ? sorted[middle]
    : ((sorted[middle - 1] ?? 0) + (sorted[middle] ?? 0)) / 2;
};

interface PairFacts {
  readonly pairId: string;
  readonly members: ReadonlyArray<string>;
  readonly formedDay: string;
  readonly formedAt: number;
  readonly widgetUsers: ReadonlySet<string>;
  /** User to the first moment they sent a note. */
  readonly firstNoteBy: ReadonlyMap<string, number>;
  /** Day to the users who sent a note on it. */
  readonly noteUsersByDay: ReadonlyMap<string, ReadonlySet<string>>;
  readonly openUsersByDay: ReadonlyMap<string, ReadonlySet<string>>;
  readonly notesByDay: ReadonlyMap<string, number>;
}

const addTo = <K, V>(map: Map<K, Set<V>>, key: K, value: V) => {
  const set = map.get(key) ?? new Set<V>();
  set.add(value);
  map.set(key, set);
};

const factsFor = (rows: ReadonlyArray<EventRow>): ReadonlyArray<PairFacts> => {
  const byPair = new Map<string, Array<EventRow>>();
  for (const row of rows) {
    if (row.pairId === "") continue;
    const list = byPair.get(row.pairId) ?? [];
    list.push(row);
    byPair.set(row.pairId, list);
  }
  const facts: Array<PairFacts> = [];
  for (const [pairId, list] of byPair) {
    const claims = list.filter(({ name }) => name === "PairClaimed");
    // A pair with no claim row has no start, so none of the day counts can be placed.
    if (claims.length === 0) continue;
    const formedAt = Math.min(...claims.map(({ firstAt }) => firstAt));
    const formedDay = claims.map(({ day }) => day).toSorted()[0] ?? "";
    const widgetUsers = new Set<string>();
    const firstNoteBy = new Map<string, number>();
    const noteUsersByDay = new Map<string, Set<string>>();
    const openUsersByDay = new Map<string, Set<string>>();
    const notesByDay = new Map<string, number>();
    for (const row of list) {
      if (row.name === "WidgetAdded") widgetUsers.add(row.userId);
      if (row.name === "NoteSent") {
        firstNoteBy.set(row.userId, Math.min(firstNoteBy.get(row.userId) ?? Infinity, row.firstAt));
        addTo(noteUsersByDay, row.day, row.userId);
        notesByDay.set(row.day, (notesByDay.get(row.day) ?? 0) + row.count);
      }
      if (row.name === "AppOpened") addTo(openUsersByDay, row.day, row.userId);
    }
    facts.push({
      pairId,
      members: [...new Set(claims.map(({ userId }) => userId))],
      formedDay,
      formedAt,
      widgetUsers,
      firstNoteBy,
      noteUsersByDay,
      openUsersByDay,
      notesByDay,
    });
  }
  return facts;
};

const bothIn = (members: ReadonlyArray<string>, present: ReadonlySet<string> | undefined) =>
  members.length === 2 && members.every((member) => present?.has(member) === true);

const bothSentOn = (pair: PairFacts, day: string) =>
  bothIn(pair.members, pair.noteUsersByDay.get(day));

const bothActiveOn = (pair: PairFacts, day: string) => {
  const active = new Set([
    ...(pair.noteUsersByDay.get(day) ?? []),
    ...(pair.openUsersByDay.get(day) ?? []),
  ]);
  return bothIn(pair.members, active);
};

const timeToFirstNote = (pair: PairFacts): number | undefined => {
  if (pair.firstNoteBy.size === 0) return undefined;
  return Math.min(...pair.firstNoteBy.values()) - pair.formedAt;
};

const timeToBothNotes = (pair: PairFacts): number | undefined =>
  bothIn(pair.members, new Set(pair.firstNoteBy.keys()))
    ? Math.max(...pair.firstNoteBy.values()) - pair.formedAt
    : undefined;

const northStar = (pairs: ReadonlyArray<PairFacts>, today: string): Share => {
  const eligible = pairs.filter((pair) => addDays(pair.formedDay, 7) <= today);
  return share(
    eligible.filter((pair) => bothSentOn(pair, addDays(pair.formedDay, 7))).length,
    eligible.length,
  );
};

/** Smallest group in which a percentage is worth more than a glance. */
export const minimumPairsPerVariant = 100;

const cautionFor = (variants: ReadonlyArray<VariantReport>): string => {
  const smallest = Math.min(...variants.map(({ northStar: n }) => n.of));
  if (smallest < minimumPairsPerVariant) {
    return `Only ${smallest} pairs in the smallest variant have reached day 7. With fewer than ${minimumPairsPerVariant} per variant, a gap of under about 15 points is noise: read the intervals, do not pick a winner.`;
  }
  return "Enough pairs to see a large gap. If the intervals overlap, there is no result yet.";
};

/**
 * Turns the stored counts into the funnel, the north-star metric and the experiment comparison.
 * Pure: the same rows and day give the same report, and it never sees a note.
 * Every figure counts pairs or people. A day is a UTC day, so a partner far from UTC can be counted
 * a day early or late; at the sizes this app will have for a long time that is smaller than the
 * noise.
 */
export const buildReport = (
  events: ReadonlyArray<EventRow>,
  flags: ReadonlyArray<FlagRow>,
  today: string,
): FunnelReport => {
  const pairs = factsFor(events);
  const inviters = new Set(
    events.filter(({ name }) => name === "InviteCreated").map(({ userId }) => userId),
  );
  const pairedUsers = new Set(pairs.flatMap(({ members }) => members));

  const days = [1, 7, 30].map((day): DayActivity => {
    const eligible = pairs.filter((pair) => addDays(pair.formedDay, day) <= today);
    const on = (pair: PairFacts) => addDays(pair.formedDay, day);
    return {
      day,
      eligible: eligible.length,
      bothSentNote: share(
        eligible.filter((pair) => bothSentOn(pair, on(pair))).length,
        eligible.length,
      ),
      bothActive: share(
        eligible.filter((pair) => bothActiveOn(pair, on(pair))).length,
        eligible.length,
      ),
    };
  });

  const weekOld = pairs.filter((pair) => addDays(pair.formedDay, 7) <= today);
  const weekRates = weekOld.map((pair) => {
    let notes = 0;
    for (let offset = 0; offset < 7; offset += 1) {
      notes += pair.notesByDay.get(addDays(pair.formedDay, offset)) ?? 0;
    }
    return notes / 7;
  });

  const perDay = new Map<string, { notes: number; pairs: Set<string> }>();
  for (const row of events) {
    if (row.name !== "NoteSent" || row.pairId === "") continue;
    const entry = perDay.get(row.day) ?? { notes: 0, pairs: new Set<string>() };
    entry.notes += row.count;
    entry.pairs.add(row.pairId);
    perDay.set(row.day, entry);
  }

  const opening = { watched: 0, skipped: 0 };
  for (const row of events) {
    if (row.name === "OpeningWatched") opening.watched += row.count;
    if (row.name === "OpeningSkipped") opening.skipped += row.count;
  }

  const byPairId = new Map(pairs.map((pair) => [pair.pairId, pair]));
  const grouped = new Map<string, Map<string, Array<PairFacts>>>();
  for (const flag of flags) {
    const pair = byPairId.get(flag.pairId);
    if (pair === undefined) continue;
    const variants = grouped.get(flag.experimentKey) ?? new Map<string, Array<PairFacts>>();
    const list = variants.get(flag.variant) ?? [];
    list.push(pair);
    variants.set(flag.variant, list);
    grouped.set(flag.experimentKey, variants);
  }
  const experiments = [...grouped]
    .toSorted(([a], [b]) => a.localeCompare(b))
    .map(([key, variants]): ExperimentReport => {
      const reports = [...variants]
        .toSorted(([a], [b]) => a.localeCompare(b))
        .map(([variant, members]): VariantReport => ({
          variant,
          pairs: members.length,
          northStar: northStar(members, today),
          medianToFirstNote: median(members.flatMap((pair) => timeToFirstNote(pair) ?? [])),
        }));
      return { key, variants: reports, caution: cautionFor(reports) };
    });

  return {
    today,
    invitesCreated: inviters.size,
    pairsFormed: pairs.length,
    inviterPaired: share(
      [...inviters].filter((user) => pairedUsers.has(user)).length,
      inviters.size,
    ),
    widgetAddedByBoth: share(
      pairs.filter((pair) => bothIn(pair.members, pair.widgetUsers)).length,
      pairs.length,
    ),
    firstNoteBothWays: share(
      pairs.filter((pair) => timeToBothNotes(pair) !== undefined).length,
      pairs.length,
    ),
    medianToFirstNote: median(pairs.flatMap((pair) => timeToFirstNote(pair) ?? [])),
    medianToFirstNoteBothWays: median(pairs.flatMap((pair) => timeToBothNotes(pair) ?? [])),
    days,
    notesPerPairPerDay: {
      pairs: weekRates.length,
      mean:
        weekRates.length === 0
          ? undefined
          : weekRates.reduce((a, b) => a + b, 0) / weekRates.length,
    },
    opening,
    daily: [...perDay]
      .toSorted(([a], [b]) => a.localeCompare(b))
      .map(([day, { notes, pairs: withNote }]) => ({ day, notes, pairsWithNote: withNote.size })),
    experiments,
  };
};
