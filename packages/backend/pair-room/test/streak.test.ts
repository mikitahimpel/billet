import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { LocalDay } from "@billet/contracts-domain/coins";
import {
  addDays,
  emptyStreak,
  type LoveStreak,
  streakDayCoins,
  streakMilestoneCoins,
} from "@billet/contracts-domain/streak";
import { activityOf } from "../src/activity.ts";
import { decide } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import { RoomRejection } from "../src/room-decision.ts";
import type { ActiveRoom, RoomState } from "../src/room-state.ts";
import { active, alice, bob, mallory, vacant } from "./samples.ts";

const day = Schema.decodeSync(LocalDay);
const hour = 3_600_000;
/** Noon UTC on 2026-11-04. */
const noon = Date.parse("2026-11-04T12:00:00Z");
const dayAt = (n: number) => noon + n * 24 * hour;

const report = (by = alice, at = noon, happenedAt = at, utcOffsetSeconds = 0) =>
  RoomCommand.cases.RecordStreakDay.make({ by, at, happenedAt, utcOffsetSeconds });
const restore = (by = alice, at = noon, utcOffsetSeconds = 0) =>
  RoomCommand.cases.RestoreStreak.make({ by, at, utcOffsetSeconds });

const run = (state: RoomState, commands: ReadonlyArray<RoomCommand>): ActiveRoom =>
  commands.reduce<ActiveRoom>((room, command) => {
    const decision = decide(room, command);
    if (decision._tag !== "Accepted") throw new Error(`expected Accepted for ${command._tag}`);
    return decision.state;
  }, state as ActiveRoom);

const streakOf = (commands: ReadonlyArray<RoomCommand>): LoveStreak => run(active, commands).streak;

/** Both partners on the day of `at`. */
const both = (at = noon): ReadonlyArray<RoomCommand> => [report(alice, at), report(bob, at)];
const days = (...ns: ReadonlyArray<number>) => ns.flatMap((n) => both(dayAt(n)));

describe("the pair's love streak", () => {
  it("lights a day once both partners did their part", () => {
    expect(streakOf([report(alice), report(alice, noon + hour)])).toEqual({
      days: 0,
      best: 0,
      marks: [{ user: alice, day: day("2026-11-04") }],
    });
    expect(streakOf([report(alice), report(bob), report(alice, noon + hour)])).toEqual({
      days: 1,
      best: 1,
      lastDay: day("2026-11-04"),
    });
    expect(streakOf(days(0, 1, 2))).toEqual({ days: 3, best: 3, lastDay: day("2026-11-06") });
  });

  it("waits for the partner and says which day", () => {
    const decision = decide(active, report(alice));
    if (decision._tag !== "Accepted") throw new Error("expected Accepted");
    expect(decision.outputs).toEqual([
      {
        _tag: "StreakChanged",
        streak: { days: 0, best: 0, marks: [{ user: alice, day: day("2026-11-04") }] },
        by: alice,
        at: noon,
        waiting: day("2026-11-04"),
      },
    ]);
  });

  it("does not light a day from one partner on one day and the other the next", () => {
    expect(streakOf([report(alice, dayAt(0)), report(bob, dayAt(1))])).toEqual({
      days: 0,
      best: 0,
      marks: [
        { user: alice, day: day("2026-11-04") },
        { user: bob, day: day("2026-11-05") },
      ],
    });
    // Alice's older mark can no longer meet one, so it goes once a later day is marked.
    expect(streakOf([report(alice, dayAt(0)), report(bob, dayAt(3))]).marks).toEqual([
      { user: bob, day: day("2026-11-07") },
    ]);
  });

  it("matches the partners' own local days across time zones", () => {
    // 23:30 UTC: Alice two hours east is on the 5th, Bob in UTC still on the 4th.
    const late = Date.parse("2026-11-04T23:30:00Z");
    const room = run(active, [report(alice, late, late, 7200), report(bob, late, late, 0)]);
    expect(room.streak.days).toBe(0);
    // Bob's next morning is the 5th: it meets Alice's mark and lights it.
    const morning = Date.parse("2026-11-05T09:00:00Z");
    expect(run(room, [report(bob, morning)]).streak).toEqual({
      days: 1,
      best: 1,
      lastDay: day("2026-11-05"),
    });
  });

  it("pays the pair for a lit day, and more at some milestones", () => {
    const room = run(active, [report(alice)]);
    const second = decide(room, report(bob, noon + hour));
    if (second._tag !== "Accepted") throw new Error("expected Accepted");
    expect(second.state.wallet.balance - room.wallet.balance).toBe(streakDayCoins);
    expect(second.outputs).toContainEqual({
      _tag: "CoinsEntered",
      entry: {
        id: "earn:streak:2026-11-04",
        kind: "earn",
        amount: streakDayCoins,
        ref: "2026-11-04",
        at: noon + hour,
      },
    });
    const six = run(active, days(0, 1, 2, 3, 4, 5));
    const seventh = run(six, days(6));
    expect(seventh.wallet.balance - six.wallet.balance).toBe(
      streakDayCoins + (streakMilestoneCoins[7] ?? 0),
    );
  });

  it("says nothing when the day already counts", () => {
    const room = run(active, both());
    expect(decide(room, report(bob, noon + hour))).toEqual({
      _tag: "Accepted",
      state: room,
      outputs: [],
    });
    const marked = run(active, [report(alice)]);
    expect(decide(marked, report(alice, noon + hour))).toEqual({
      _tag: "Accepted",
      state: marked,
      outputs: [],
    });
  });

  it("starts over after a missed day and keeps the best", () => {
    expect(streakOf(days(0, 1, 3))).toEqual({ days: 1, best: 2, lastDay: day("2026-11-07") });
  });

  it("counts the day it happened on after a time offline, at most one day back", () => {
    // Done last night at 23:00, reported this morning: yesterday counts.
    const late = report(alice, dayAt(1) - 3 * hour, noon + 11 * hour);
    expect(streakOf([report(bob, noon), late]).lastDay).toBe(day("2026-11-04"));
    expect(streakOf([...days(-1), report(bob, noon), late])).toMatchObject({ days: 2 });
    // A claim from three days back is held to a day before the room's clock.
    expect(streakOf([report(bob, dayAt(2)), report(alice, dayAt(3), noon)]).lastDay).toBe(
      day("2026-11-06"),
    );
    // Nor can a phone count a day the room's clock has not reached.
    expect(streakOf([report(bob, noon), report(alice, noon, dayAt(5))]).lastDay).toBe(
      day("2026-11-04"),
    );
  });

  it("counts the day in the caller's own clock", () => {
    // 23:30 UTC is already the next day two hours east.
    const late = Date.parse("2026-11-04T23:30:00Z");
    const east = [report(alice, late, late, 7200), report(bob, late, late, 7200)];
    expect(streakOf(east).lastDay).toBe(day("2026-11-05"));
  });

  it("tells the Inbox once a day reaches a milestone", () => {
    const room = run(active, [...days(0, 1), report(alice, dayAt(2))]);
    const decision = decide(room, report(bob, dayAt(2)));
    if (decision._tag !== "Accepted") throw new Error("expected Accepted");
    expect(decision.outputs[0]).toEqual({
      _tag: "StreakChanged",
      streak: { days: 3, best: 3, lastDay: day("2026-11-06") },
      by: bob,
      at: dayAt(2),
      lit: day("2026-11-06"),
      reached: 3,
    });
    expect(activityOf(decision.outputs, dayAt(2))).toEqual([
      {
        id: "streak:2026-11-06",
        at: dayAt(2),
        doer: { _tag: "Member", user: bob },
        event: { _tag: "StreakReached", days: 3 },
      },
    ]);
    const before = decide(
      run(active, [...days(0), report(alice, dayAt(1))]),
      report(bob, dayAt(1)),
    );
    expect(before._tag === "Accepted" && activityOf(before.outputs, dayAt(1))).toEqual([]);
  });

  it("restores a streak that went out yesterday, once in thirty days for the pair", () => {
    const out = run(active, days(0, 1, 2));
    // Day 3 was missed; on day 4 it can still come back, and Alice's mark today stays.
    const restored = run(out, [report(alice, dayAt(4)), restore(bob, dayAt(4))]);
    expect(restored.streak).toEqual({
      days: 3,
      best: 3,
      lastDay: day("2026-11-07"),
      restoredOn: day("2026-11-08"),
      marks: [{ user: alice, day: day("2026-11-08") }],
    });
    expect(run(restored, [report(bob, dayAt(4))]).streak).toMatchObject({ days: 4 });
    // The partner cannot restore again the next week: the cooldown is the pair's.
    const again = run(restored, [report(bob, dayAt(4)), ...days(5)]);
    expect(decide(again, restore(alice, dayAt(7)))).toEqual({
      _tag: "Rejected",
      rejection: RoomRejection.cases.StreakNotRestorable.make({}),
    });
  });

  it.each([
    ["alive today", days(3), dayAt(3)],
    ["alive yesterday", days(3), dayAt(4)],
    ["out for two days", [], dayAt(5)],
  ])("refuses a restore of a streak %s", (_, more, at) => {
    expect(decide(run(active, [...days(0, 1, 2), ...more]), restore(alice, at))._tag).toBe(
      "Rejected",
    );
  });

  it("refuses a restore of a streak too short to be worth one", () => {
    const two = run(active, days(0, 1));
    expect(decide(two, restore(alice, dayAt(3)))._tag).toBe("Rejected");
  });

  it("is the couple's alone", () => {
    expect(decide(active, report(mallory))).toEqual({
      _tag: "Rejected",
      rejection: RoomRejection.cases.NotAMember.make({ user: mallory }),
    });
    expect(decide(vacant, report())).toEqual({
      _tag: "Rejected",
      rejection: RoomRejection.cases.RoomNotOpen.make({}),
    });
    expect(active.streak).toEqual(emptyStreak);
  });

  it("steps local days across months and years", () => {
    expect(addDays(day("2026-12-31"), 1)).toBe("2027-01-01");
    expect(addDays(day("2026-03-01"), -1)).toBe("2026-02-28");
  });
});
