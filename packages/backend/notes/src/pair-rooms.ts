import { Context, type Effect } from "effect";
import type { CatEntry, NatureSeed } from "@billet/contracts-domain/cat";
import type { UserId } from "@billet/contracts-domain/ids";
import type { InkId } from "@billet/contracts-domain/inks";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type {
  CatResponse,
  RecordCatEventRequest,
  SaveCatRequest,
} from "@billet/contracts-http-api/cat";
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
     * Deletes every note `user` sent in the room and returns them, deletes the cat and its
     * journal, and closes the room's sockets: the pair is ending. Safe to repeat.
     */
    readonly forgetMember: (
      pairId: PairId,
      user: UserId,
    ) => Effect.Effect<ReadonlyArray<SequencedNote>, NotesUnavailable>;
    /** Adopts the cat, or renames it. `natureSeed` is used only by the adoption. */
    readonly saveCat: (
      pairId: PairId,
      user: UserId,
      request: SaveCatRequest,
      natureSeed: NatureSeed,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    readonly recordCatEvent: (
      pairId: PairId,
      user: UserId,
      request: RecordCatEventRequest,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    /** The cat now, or null while the room is not open. */
    readonly cat: (pairId: PairId) => Effect.Effect<CatResponse | null, NotesUnavailable>;
    /** Journal entries with `seq` above `afterSeq`, in order. */
    readonly catJournal: (
      pairId: PairId,
      afterSeq: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<CatEntry>, NotesUnavailable>;
  }
>()("@billet/backend-notes/PairRooms") {}
