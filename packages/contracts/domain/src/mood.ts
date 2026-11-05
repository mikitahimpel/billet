import { Schema } from "effect";
import { EpochMillis, UserId } from "./ids.ts";

/** How a partner says they feel. The phone owns the face and the words; the wire carries the id. */
export const Mood = Schema.Literals(["happy", "sleepy", "missing", "busy"]);
export type Mood = typeof Mood.Type;

/** The most UTF-16 code units a check-in's note keeps, after trimming. */
export const moodNoteMaxLength = 80;

/** A few words with a check-in, trimmed and never empty. */
export const MoodNote = Schema.String.check(
  Schema.isTrimmed(),
  Schema.isNonEmpty(),
  Schema.isMaxLength(moodNoteMaxLength),
);
export type MoodNote = typeof MoodNote.Type;

/** One partner's latest check-in. The room keeps one per member; a new one replaces it. */
export const MoodCheckIn = Schema.Struct({
  user: UserId,
  mood: Mood,
  note: Schema.optionalKey(MoodNote),
  at: EpochMillis,
});
export type MoodCheckIn = typeof MoodCheckIn.Type;
