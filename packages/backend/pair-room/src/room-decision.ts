import { Schema } from "effect";
import { CatEntry, CatProfile } from "@billet/contracts-domain/cat";
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
  /** `adopted` is true for the save that brought the cat home. */
  CatSaved: { cat: CatProfile, by: UserId, adopted: Schema.Boolean },
  /** A journal entry to store: one a phone recorded, or the room's own for a stored note. */
  CatEntryAppended: { entry: CatEntry },
  /** A record whose `id` the room already holds: nothing is stored or fanned out. */
  CatEntryRepeated: { entry: CatEntry },
});
export type RoomOutput = typeof RoomOutput.Type;

export const RoomRejection = Schema.TaggedUnion({
  /** A room is opened for two different people. */
  DuplicateMember: {},
  RoomNotOpen: {},
  /** The room already belongs to a different couple. */
  RoomAlreadyOpen: {},
  NotAMember: { user: UserId },
  /** There is no cat to care for until one of the couple adopts it. */
  CatNotAdopted: {},
  /** The other partner already recorded an entry under this `id`. */
  CatEntryIdTaken: {},
});
export type RoomRejection = typeof RoomRejection.Type;

export const RoomDecision = Schema.TaggedUnion({
  /** An accepted command always leaves the room active, so `Vacant` is never persisted. */
  Accepted: { state: RoomState.cases.Active, outputs: Schema.Array(RoomOutput) },
  Rejected: { rejection: RoomRejection },
});
export type RoomDecision = typeof RoomDecision.Type;
