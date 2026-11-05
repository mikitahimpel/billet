import { Schema } from "effect";
import { Mood } from "@billet/contracts-domain/mood";

/**
 * `PUT /v1/mood`: how the caller feels now, answered with the stored `MoodCheckIn`. The room trims
 * `note` and drops it when blank; one longer than `moodNoteMaxLength` after trimming is a 400.
 */
export const SetMoodRequest = Schema.Struct({
  mood: Mood,
  note: Schema.optionalKey(Schema.String),
});
export type SetMoodRequest = typeof SetMoodRequest.Type;
