import { describe, expect, it } from "vitest";
import { addDays, type EventRow } from "@billet/backend-metrics/funnel";
import { buildAppEvents } from "../src/admin-app-events.ts";
import { buildOverview, rangeOf } from "../src/admin-overview.ts";

const today = "2026-11-04";
const row = (
  name: EventRow["name"],
  userId: string,
  day: string,
  pairId = "",
  count = 1,
): EventRow => ({ pairId, userId, name, day, count, firstAt: Date.parse(`${day}T10:00:00Z`) });

/** A pair formed `age` days ago by `a` (who invited) and `b`, both active on the listed days. */
const pair = (id: string, a: string, b: string, age: number, activeOn: ReadonlyArray<number>) => {
  const formed = addDays(today, -age);
  return [
    row("InviteCreated", a, formed),
    row("PairClaimed", a, formed, id),
    row("PairClaimed", b, formed, id),
    ...activeOn.flatMap((offset) => [
      row("AppOpened", a, addDays(formed, offset), id),
      row("NoteSent", b, addDays(formed, offset), id, 2),
    ]),
  ];
};

describe("the overview ranges", () => {
  it("reads 7, 30 and 90 days, and anything else as 30", () => {
    expect([7, 30, 90, 8, undefined].map(rangeOf)).toEqual([7, 30, 90, 30, 30]);
  });

  it("covers the range ending today and the one before it", () => {
    const o = buildOverview([], [], 0, today, 7);
    expect(o.range).toEqual({
      days: 7,
      from: "2026-10-29",
      to: today,
      previousFrom: "2026-10-22",
      previousTo: "2026-10-28",
    });
    expect(o.daily.map(({ day }) => day)).toEqual(
      Array.from({ length: 7 }, (_, i) => addDays("2026-10-29", i)),
    );
  });

  it("has no rates without data, rather than zeros", () => {
    const { stats } = buildOverview([], [], 0, today, 7);
    expect(stats.dau).toMatchObject({ current: 0, previous: 0 });
    expect(stats.notesPerPairPerDay).toMatchObject({ current: null, previous: null });
    expect(stats.notesPerPairPerDay.series.every((value) => value === null)).toBe(true);
    expect(stats.pairCompletion.current).toMatchObject({ of: 0, share: undefined });
    expect(stats.d7.current).toMatchObject({ of: 0, share: undefined });
  });
});

describe("the stat cards", () => {
  // p-new formed 3 days ago (this week), p-old 10 days ago (the week before).
  const events = [
    ...pair("p-new", "a1", "b1", 3, [0, 1, 2, 3]),
    ...pair("p-old", "a2", "b2", 10, [0, 1, 7]),
    // An inviter this week who never paired.
    row("InviteCreated", "lonely", addDays(today, -1)),
  ];
  const { stats, daily } = buildOverview(events, [], 5, today, 7);

  it("sums new pairs per range, with a daily series", () => {
    expect(stats.newPairs).toMatchObject({ current: 1, previous: 1 });
    expect(stats.newPairs.series).toEqual([0, 0, 0, 1, 0, 0, 0]);
  });

  it("averages daily active people and takes weekly active on the last day", () => {
    expect(stats.dau.series).toEqual(daily.map(({ dau }) => dau));
    const total = daily.reduce((sum, { dau }) => sum + dau, 0);
    expect(stats.dau.current).toBeCloseTo(total / 7);
    expect(stats.wau.current).toBe(daily.at(-1)?.wau);
  });

  it("divides notes by the days each pair existed", () => {
    // This week: p-old exists all 7 days, p-new the last 4: 11 pair-days. Notes: p-new 4 days × 2,
    // p-old on its day 7 (3 days ago) × 2 = 10.
    expect(stats.notesPerPairPerDay.current).toBeCloseTo(10 / 11);
    // The week before: p-old for its first 4 days, notes on days 0 and 1 (2 × 2 = 4).
    expect(stats.notesPerPairPerDay.previous).toBeCloseTo(4 / 4);
    expect(stats.notesPerPairPerDay.series[0]).toBe(0);
  });

  it("counts pair completion for inviters whose first invite fell in the range", () => {
    expect(stats.pairCompletion.current).toMatchObject({ of: 2, count: 1 });
    expect(stats.pairCompletion.previous).toMatchObject({ of: 1, count: 1 });
  });

  it("measures D1 and D7 on the pairs that formed in each range", () => {
    expect(stats.d1.current).toMatchObject({ of: 1, count: 1 });
    expect(stats.d1.previous).toMatchObject({ of: 1, count: 1 });
    // p-new is 3 days old: not eligible for D7. p-old was active on its day 7.
    expect(stats.d7.current).toMatchObject({ of: 0 });
    expect(stats.d7.previous).toMatchObject({ of: 1, count: 1 });
  });
});

describe("the events in the app", () => {
  const events = [
    row("AppOpened", "u1", today, "p1", 3),
    row("AppOpened", "u2", addDays(today, -2), "p1"),
    row("AppOpened", "u3", addDays(today, -9), "p2", 5),
    row("OpeningSkipped", "u1", addDays(today, -40), "p1"),
  ];
  const result = buildAppEvents(events, today, 7);
  const byName = (name: string) => result.events.find((event) => event.name === name);

  it("lists every event the contract knows, recorded ones first", () => {
    expect(result.events.map(({ name }) => name).toSorted()).toEqual(
      [
        "AppOpened",
        "InviteCreated",
        "NoteSent",
        "OpeningSkipped",
        "OpeningWatched",
        "PairClaimed",
        "WidgetAdded",
      ].toSorted(),
    );
    expect(result.events.slice(0, 2).map(({ name }) => name)).toEqual([
      "AppOpened",
      "OpeningSkipped",
    ]);
  });

  it("counts per day, against the range before, and the pairs of the last week", () => {
    expect(byName("AppOpened")).toMatchObject({
      source: "app",
      total: 4,
      previousTotal: 5,
      daily: [0, 0, 0, 0, 1, 0, 3],
      pairs7d: 1,
      people: 2,
      firstDay: addDays(today, -9),
      lastDay: today,
    });
  });

  it("says when an event last landed even outside the range", () => {
    expect(byName("OpeningSkipped")).toMatchObject({ total: 0, lastDay: addDays(today, -40) });
    expect(byName("NoteSent")).toMatchObject({ source: "server", firstDay: null, lastDay: null });
  });
});
