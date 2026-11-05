import { Schema } from "effect";
import { EpochMillis, NoteId, UserId } from "./ids.ts";

/** What a partner can answer a photo with. The phone owns the emoji; the wire carries the id. */
export const Reaction = Schema.Literals(["heart", "laugh", "wow", "sad", "fire"]);
export type Reaction = typeof Reaction.Type;

/**
 * One partner's reaction to one note, at its latest. `reaction` is absent once they took it back,
 * so a client that resumes after `rev` learns of that too. `rev` orders every change in the room.
 */
export const NoteReaction = Schema.Struct({
  rev: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)),
  note: NoteId,
  by: UserId,
  at: EpochMillis,
  reaction: Schema.optionalKey(Reaction),
});
export type NoteReaction = typeof NoteReaction.Type;
