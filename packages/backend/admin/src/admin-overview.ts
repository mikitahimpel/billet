import {
  addDays,
  buildReport,
  type EventRow,
  type FlagRow,
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

export type FunnelStep = "install" | "signedIn" | "paired" | "firstNote" | "secondDay";

export interface Overview {
  readonly today: string;
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

/**
 * The Overview page, from the D1 counts. Pure, like `buildReport`, which it reuses for the pair
 * figures. DAU and WAU count people; a day is a UTC day.
 */
export const buildOverview = (
  events: ReadonlyArray<EventRow>,
  flags: ReadonlyArray<FlagRow>,
  userCount: number,
  today: string,
  days = 30,
): Overview => {
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

  const daily = Array.from({ length: days }, (_, index): DailyPoint => {
    const day = addDays(today, index - days + 1);
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

  const usersWith = (name: EventRow["name"]) =>
    new Set(events.filter((row) => row.name === name).map(({ userId }) => userId)).size;

  return {
    today,
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
