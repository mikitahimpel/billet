import { Schema } from "effect";
import { LocalDay } from "./coins.ts";

const Count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/**
 * The couple's love streak, one for the pair (docs/love-streak.md). `days` is the run of days in a
 * row up to `lastDay`, kept after the streak breaks so a restore can bring it back. `restoredOn` is
 * the day the pair last used its restore, so the cooldown is shared by both partners.
 */
export const LoveStreak = Schema.Struct({
  days: Count,
  best: Count,
  lastDay: Schema.optionalKey(LocalDay),
  restoredOn: Schema.optionalKey(LocalDay),
});
export type LoveStreak = typeof LoveStreak.Type;

export const emptyStreak: LoveStreak = { days: 0, best: 0 };

/** The streak lengths the couple is told about. */
export const streakMilestones: ReadonlyArray<number> = [3, 7, 14, 30, 50, 100, 200, 365];

/** Days between restores. */
export const streakRestoreCooldown = 30;
/** Shorter streaks aren't worth a restore. */
export const streakRestoreMinimum = 3;

const dayMillis = 86_400_000;

/** Whole days from `from` to `to`, both local days. */
export const daysBetween = (from: LocalDay, to: LocalDay): number =>
  Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / dayMillis);

const decodeDay = Schema.decodeSync(LocalDay);

/** The local day `days` after `day`; negative goes back. */
export const addDays = (day: LocalDay, days: number): LocalDay =>
  decodeDay(new Date(Date.parse(`${day}T00:00:00Z`) + days * dayMillis).toISOString().slice(0, 10));

const canRestore = (streak: LoveStreak, today: LocalDay): boolean =>
  streak.days >= streakRestoreMinimum &&
  (streak.restoredOn === undefined ||
    daysBetween(streak.restoredOn, today) >= streakRestoreCooldown);

/** Whether the streak went out after one missed day and can still be brought back `today`. */
export const isRestorable = (streak: LoveStreak, today: LocalDay): boolean =>
  streak.lastDay !== undefined &&
  streak.days > 0 &&
  daysBetween(streak.lastDay, today) === 2 &&
  canRestore(streak, today);

/**
 * The streak after something the couple did on `day`: the first of a day grows it, the day after
 * the last one continues it, a later one starts over. A day before the last one changes nothing.
 */
export const recordStreakDay = (streak: LoveStreak, day: LocalDay): LoveStreak => {
  if (streak.lastDay !== undefined && daysBetween(streak.lastDay, day) <= 0) return streak;
  const days =
    streak.lastDay !== undefined && daysBetween(streak.lastDay, day) === 1 ? streak.days + 1 : 1;
  return { ...streak, days, lastDay: day, best: Math.max(streak.best, days) };
};

/** Fills in the missed day, so today's first action continues the old streak. */
export const restoreStreak = (streak: LoveStreak, today: LocalDay): LoveStreak | undefined =>
  isRestorable(streak, today)
    ? { ...streak, lastDay: addDays(today, -1), restoredOn: today }
    : undefined;
