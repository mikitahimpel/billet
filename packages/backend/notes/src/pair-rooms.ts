import { Context, type Effect } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { InkId } from "@billet/contracts-domain/inks";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import type { RoomDecision } from "@billet/backend-pair-room/room-decision";
import type { SequencedNote } from "@billet/backend-pair-room/room-state";
import type { NotesUnavailable } from "./notes-error.ts";

/** Reaches the `PairRoom` of a couple. Failing to reach it is `NotesUnavailable`. */
export class PairRooms extends Context.Service<
  PairRooms,
  {
    readonly open: (
      pairId: PairId,
      members: readonly [UserId, UserId],
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    readonly sendNote: (
      pairId: PairId,
      author: UserId,
      request: SendNoteRequest,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    /** The ink colours the pair bought, in the order it got them. Never the free ink. */
    readonly inks: (pairId: PairId) => Effect.Effect<ReadonlyArray<InkId>, NotesUnavailable>;
    /** Gives the pair ink colours it does not have yet. Safe to repeat. */
    readonly grantInks: (
      pairId: PairId,
      inks: ReadonlyArray<InkId>,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    /** Notes with `seq` above `afterSeq`, in order. */
    readonly notesAfter: (
      pairId: PairId,
      afterSeq: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<SequencedNote>, NotesUnavailable>;
    /**
     * Deletes every note `user` sent in the room and returns them, and closes the room's sockets:
     * the pair is ending. Safe to repeat.
     */
    readonly forgetMember: (
      pairId: PairId,
      user: UserId,
    ) => Effect.Effect<ReadonlyArray<SequencedNote>, NotesUnavailable>;
  }
>()("@billet/backend-notes/PairRooms") {}
