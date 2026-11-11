import { Schema } from "effect";
import { LocalDay } from "./coins.ts";
import { UserId } from "./ids.ts";

const Count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** A member did their part on `day`, their own local day, which isn't lit yet. */
export const StreakMark = Schema.Struct({ user: UserId, day: LocalDay });
export type StreakMark = typeof StreakMark.Type;

/** One per pair (docs/love-streak.md). `days` is kept after a break so a restore can bring it
 * back. `restoredOn` is per pair, so both partners share the cooldown. `marks` are the days after
 * `lastDay` only one partner has done yet. */
export const LoveStreak = Schema.Struct({
  days: Count,
  best: Count,
  lastDay: Schema.optionalKey(LocalDay),
  restoredOn: Schema.optionalKey(LocalDay),
  marks: Schema.optionalKey(Schema.Array(StreakMark)),
});
export type LoveStreak = typeof LoveStreak.Type;

export const emptyStreak: LoveStreak = { days: 0, best: 0 };

export const streakMilestones: ReadonlyArray<number> = [3, 7, 14, 30, 50, 100, 200, 365];

/** Coins a lit day pays the pair. */
export const streakDayCoins = 10;

/** What a lit day pays on top when it reaches one of these. */
export const streakMilestoneCoins: Readonly<Record<number, number>> = {
  7: 25,
  30: 50,
  100: 100,
  365: 200,
};

/** Days between restores. */
export const streakRestoreCooldown = 30;
/** Shorter streaks aren't worth a restore. */
export const streakRestoreMinimum = 3;

const dayMillis = 86_400_000;

export const daysBetween = (from: LocalDay, to: LocalDay): number =>
  Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / dayMillis);

const decodeDay = Schema.decodeSync(LocalDay);

/** Negative `days` goes back. */
export const addDays = (day: LocalDay, days: number): LocalDay =>
  decodeDay(new Date(Date.parse(`${day}T00:00:00Z`) + days * dayMillis).toISOString().slice(0, 10));

const canRestore = (streak: LoveStreak, today: LocalDay): boolean =>
  streak.days >= streakRestoreMinimum &&
  (streak.restoredOn === undefined ||
    daysBetween(streak.restoredOn, today) >= streakRestoreCooldown);

/** Only after exactly one missed day. */
export const isRestorable = (streak: LoveStreak, today: LocalDay): boolean =>
  streak.lastDay !== undefined &&
  streak.days > 0 &&
  daysBetween(streak.lastDay, today) === 2 &&
  canRestore(streak, today);

/** The day after `lastDay` continues it, a later one starts over, an earlier or same one changes
 * nothing. */
export const recordStreakDay = (streak: LoveStreak, day: LocalDay): LoveStreak => {
  if (streak.lastDay !== undefined && daysBetween(streak.lastDay, day) <= 0) return streak;
  const days =
    streak.lastDay !== undefined && daysBetween(streak.lastDay, day) === 1 ? streak.days + 1 : 1;
  return { ...streak, days, lastDay: day, best: Math.max(streak.best, days) };
};

/** A mark further back than this from the newest can no longer meet the partner's. Partners' local
 * days differ by at most one across time zones. */
const markReach = 1;

/** No `marks` key when there are none, so an unmarked streak reads as it did before marks. */
const withMarks = (streak: LoveStreak, marks: ReadonlyArray<StreakMark>): LoveStreak => {
  const { days, best, lastDay, restoredOn } = streak;
  return {
    days,
    best,
    ...(lastDay === undefined ? {} : { lastDay }),
    ...(restoredOn === undefined ? {} : { restoredOn }),
    ...(marks.length === 0 ? {} : { marks }),
  };
};

/**
 * `user` did their part on `day`. The day lights once both members have marked it; until then the
 * mark waits. A day at or before `lastDay` changes nothing.
 */
export const markStreakDay = (
  streak: LoveStreak,
  members: readonly [UserId, UserId],
  user: UserId,
  day: LocalDay,
): LoveStreak => {
  if (streak.lastDay !== undefined && daysBetween(streak.lastDay, day) <= 0) return streak;
  const marks = streak.marks ?? [];
  if (marks.some((mark) => mark.user === user && mark.day === day)) return streak;
  const partner = members[0] === user ? members[1] : members[0];
  if (marks.some((mark) => mark.user === partner && mark.day === day)) {
    const lit = recordStreakDay(withMarks(streak, []), day);
    return withMarks(
      lit,
      marks.filter((mark) => daysBetween(day, mark.day) > 0),
    );
  }
  const added = [...marks, { user, day }];
  const newest = added.reduce((max, mark) => (mark.day > max ? mark.day : max), day);
  return withMarks(
    streak,
    added.filter((mark) => daysBetween(mark.day, newest) <= markReach),
  );
};

/** Whether `user` has done their part on `day`: marked it, or it is lit. */
export const hasMarked = (streak: LoveStreak, user: UserId, day: LocalDay): boolean =>
  streak.lastDay === day ||
  (streak.marks ?? []).some((mark) => mark.user === user && mark.day === day);

/** Fills in the missed day, so today's first action continues the old streak. */
export const restoreStreak = (streak: LoveStreak, today: LocalDay): LoveStreak | undefined => {
  if (!isRestorable(streak, today)) return undefined;
  const lastDay = addDays(today, -1);
  const marks = (streak.marks ?? []).filter((mark) => daysBetween(lastDay, mark.day) > 0);
  return withMarks({ ...streak, lastDay, restoredOn: today }, marks);
};
