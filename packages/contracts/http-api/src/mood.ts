import { Schema } from "effect";
import { Mood } from "@billet/contracts-domain/mood";

/** `PUT /v1/mood`. `note` is trimmed and dropped when blank; over `moodNoteMaxLength` is a 400. */
export const SetMoodRequest = Schema.Struct({
  mood: Mood,
  note: Schema.optionalKey(Schema.String),
});
export type SetMoodRequest = typeof SetMoodRequest.Type;
