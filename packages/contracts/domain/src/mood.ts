import { Schema } from "effect";
import { EpochMillis, UserId } from "./ids.ts";

/** The phone owns the face and the words; the wire carries the id. */
export const Mood = Schema.Literals(["happy", "sleepy", "missing", "busy"]);
export type Mood = typeof Mood.Type;

/** UTF-16 code units, after trimming. */
export const moodNoteMaxLength = 80;

export const MoodNote = Schema.String.check(
  Schema.isTrimmed(),
  Schema.isNonEmpty(),
  Schema.isMaxLength(moodNoteMaxLength),
);
export type MoodNote = typeof MoodNote.Type;

/** The room keeps one per member; a new one replaces it. */
export const MoodCheckIn = Schema.Struct({
  user: UserId,
  mood: Mood,
  note: Schema.optionalKey(MoodNote),
  at: EpochMillis,
});
export type MoodCheckIn = typeof MoodCheckIn.Type;
