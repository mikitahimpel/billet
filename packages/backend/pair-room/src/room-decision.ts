import { Schema } from "effect";
import { IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PresenceState } from "@billet/contracts-realtime/client-message";
import { RoomState, SequencedNote } from "./room-state.ts";

/**
 * What an accepted command asks the outside world to do, like an `Output` on the Swift side.
 * `NoteAppended` is stored today. The relay (#17) and push fan-out (#19) read the same outputs.
 * `NoteRepeated` answers a send whose key the room already holds: nothing is stored or fanned out.
 */
export const RoomOutput = Schema.TaggedUnion({
  RoomOpened: { pairId: PairId },
  NoteAppended: { entry: SequencedNote, key: IdempotencyKey },
  NoteRepeated: { entry: SequencedNote },
  PresenceChanged: { user: UserId, state: PresenceState },
});
export type RoomOutput = typeof RoomOutput.Type;

export const RoomRejection = Schema.TaggedUnion({
  /** A room is opened for two different people. */
  DuplicateMember: {},
  RoomNotOpen: {},
  /** The room already belongs to a different couple. */
  RoomAlreadyOpen: {},
  NotAMember: { user: UserId },
});
export type RoomRejection = typeof RoomRejection.Type;

export const RoomDecision = Schema.TaggedUnion({
  /** An accepted command always leaves the room active, so `Vacant` is never persisted. */
  Accepted: { state: RoomState.cases.Active, outputs: Schema.Array(RoomOutput) },
  Rejected: { rejection: RoomRejection },
});
export type RoomDecision = typeof RoomDecision.Type;
