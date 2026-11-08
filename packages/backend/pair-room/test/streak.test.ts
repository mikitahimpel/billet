import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { LocalDay } from "@billet/contracts-domain/coins";
import { addDays, emptyStreak, type LoveStreak } from "@billet/contracts-domain/streak";
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

describe("the pair's love streak", () => {
  it("counts one day for the pair, whichever partner reports it", () => {
    expect(streakOf([report(alice), report(bob), report(alice, noon + hour)])).toEqual({
      days: 1,
      best: 1,
      lastDay: day("2026-11-04"),
    });
    expect(streakOf([report(alice), report(bob, dayAt(1)), report(alice, dayAt(2))])).toEqual({
      days: 3,
      best: 3,
      lastDay: day("2026-11-06"),
    });
  });

  it("says nothing when the day already counts", () => {
    const room = run(active, [report(alice)]);
    expect(decide(room, report(bob, noon + hour))).toEqual({
      _tag: "Accepted",
      state: room,
      outputs: [],
    });
  });

  it("starts over after a missed day and keeps the best", () => {
    expect(streakOf([report(), report(alice, dayAt(1)), report(alice, dayAt(3))])).toEqual({
      days: 1,
      best: 2,
      lastDay: day("2026-11-07"),
    });
  });

  it("counts the day it happened on after a time offline, at most one day back", () => {
    // Done last night at 23:00, reported this morning: yesterday counts.
    const late = report(alice, dayAt(1) - 3 * hour, noon + 11 * hour);
    expect(streakOf([report(alice, noon), late]).lastDay).toBe(day("2026-11-04"));
    expect(streakOf([report(alice, dayAt(-1)), late])).toMatchObject({ days: 2 });
    // A claim from three days back is held to a day before the room's clock.
    expect(streakOf([report(alice, dayAt(3), noon)]).lastDay).toBe(day("2026-11-06"));
    // Nor can a phone count a day the room's clock has not reached.
    expect(streakOf([report(alice, noon, dayAt(5))]).lastDay).toBe(day("2026-11-04"));
  });

  it("counts the day in the caller's own clock", () => {
    // 23:30 UTC is already the next day two hours east.
    const late = Date.parse("2026-11-04T23:30:00Z");
    expect(streakOf([report(alice, late, late, 7200)]).lastDay).toBe(day("2026-11-05"));
  });

  it("tells the Inbox once a day reaches a milestone", () => {
    const room = run(active, [report(alice, dayAt(0)), report(alice, dayAt(1))]);
    const decision = decide(room, report(bob, dayAt(2)));
    if (decision._tag !== "Accepted") throw new Error("expected Accepted");
    expect(decision.outputs).toEqual([
      {
        _tag: "StreakChanged",
        streak: { days: 3, best: 3, lastDay: day("2026-11-06") },
        by: bob,
        at: dayAt(2),
        reached: 3,
      },
    ]);
    expect(activityOf(decision.outputs, dayAt(2))).toEqual([
      {
        id: "streak:2026-11-06",
        at: dayAt(2),
        doer: { _tag: "Member", user: bob },
        event: { _tag: "StreakReached", days: 3 },
      },
    ]);
    const before = decide(room, report(bob, dayAt(1) + hour));
    expect(before._tag === "Accepted" && activityOf(before.outputs, dayAt(1))).toEqual([]);
  });

  it("restores a streak that went out yesterday, once in thirty days for the pair", () => {
    const three = [report(alice, dayAt(0)), report(alice, dayAt(1)), report(alice, dayAt(2))];
    const out = run(active, three);
    // Day 3 was missed; on day 4 it can still come back.
    const restored = run(out, [restore(bob, dayAt(4))]);
    expect(restored.streak).toEqual({
      days: 3,
      best: 3,
      lastDay: day("2026-11-07"),
      restoredOn: day("2026-11-08"),
    });
    expect(run(restored, [report(alice, dayAt(4))]).streak).toMatchObject({ days: 4 });
    // The partner cannot restore again the next week: the cooldown is the pair's.
    const again = run(restored, [report(alice, dayAt(4)), report(alice, dayAt(5))]);
    expect(decide(again, restore(alice, dayAt(7)))).toEqual({
      _tag: "Rejected",
      rejection: RoomRejection.cases.StreakNotRestorable.make({}),
    });
  });

  it.each([
    ["alive today", [report(alice, dayAt(3))], dayAt(3)],
    ["alive yesterday", [report(alice, dayAt(3))], dayAt(4)],
    ["out for two days", [], dayAt(5)],
  ])("refuses a restore of a streak %s", (_, more, at) => {
    const three = [report(alice, dayAt(0)), report(alice, dayAt(1)), report(alice, dayAt(2))];
    expect(decide(run(active, [...three, ...more]), restore(alice, at))._tag).toBe("Rejected");
  });

  it("refuses a restore of a streak too short to be worth one", () => {
    const two = run(active, [report(alice, dayAt(0)), report(alice, dayAt(1))]);
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
