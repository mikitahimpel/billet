import { Schema } from "effect";
import { EpochMillis, NoteId, UserId } from "./ids.ts";

/** The phone owns the emoji; the wire carries the id. */
export const Reaction = Schema.Literals(["heart", "laugh", "wow", "sad", "fire"]);
export type Reaction = typeof Reaction.Type;

/** `reaction` is absent once taken back, so a client resuming after `rev` learns of it too. `rev`
 * orders every change in the room. */
export const NoteReaction = Schema.Struct({
  rev: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)),
  note: NoteId,
  by: UserId,
  at: EpochMillis,
  reaction: Schema.optionalKey(Reaction),
});
export type NoteReaction = typeof NoteReaction.Type;
