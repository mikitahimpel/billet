import { Context, type Effect } from "effect";
import type { ActiveRoom, RoomState, SequencedNote } from "./room-state.ts";

/** A room's durable storage. Failures are defects: the room cannot act without its storage. */
export class RoomStore extends Context.Service<
  RoomStore,
  {
    readonly load: Effect.Effect<RoomState>;
    /** Saves the state and appends the notes as one atomic write. */
    readonly commit: (room: ActiveRoom, notes: ReadonlyArray<SequencedNote>) => Effect.Effect<void>;
    /** Notes with `seq` above `afterSeq`, in order. */
    readonly notesAfter: (
      afterSeq: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<SequencedNote>>;
  }
>()("@billet/backend-pair-room/RoomStore") {}
