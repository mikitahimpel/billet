import { Context, type Effect, type Option } from "effect";
import type { CatEntry } from "@billet/contracts-domain/cat";
import type { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import type { ActiveRoom, RoomState, SequencedNote } from "./room-state.ts";

/** A note to store, with the key its author sent it under. */
export type AppendedNote = { readonly entry: SequencedNote; readonly key: IdempotencyKey };

/** A room's durable storage. Failures are defects: the room cannot act without its storage. */
export class RoomStore extends Context.Service<
  RoomStore,
  {
    readonly load: Effect.Effect<RoomState>;
    /** Saves the state, the cat, and appends the notes and journal entries as one atomic write. */
    readonly commit: (
      room: ActiveRoom,
      notes: ReadonlyArray<AppendedNote>,
      catEntries: ReadonlyArray<CatEntry>,
    ) => Effect.Effect<void>;
    /** The note `author` stored under `key`, if the room still holds it. */
    readonly noteByKey: (
      author: UserId,
      key: IdempotencyKey,
    ) => Effect.Effect<Option.Option<SequencedNote>>;
    /** Notes with `seq` above `afterSeq`, in order. */
    readonly notesAfter: (
      afterSeq: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<SequencedNote>>;
    /** The journal entry stored under `id`, if any. */
    readonly catEntryById: (id: IdempotencyKey) => Effect.Effect<Option.Option<CatEntry>>;
    /** Journal entries with `seq` above `afterSeq`, in order. */
    readonly catEntriesAfter: (
      afterSeq: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<CatEntry>>;
    /** Every journal entry stored at or after `since`, in order: what the needs fold reads. */
    readonly catEntriesSince: (since: EpochMillis) => Effect.Effect<ReadonlyArray<CatEntry>>;
    /** Deletes the cat and its whole journal: the pair is ending. */
    readonly forgetCat: Effect.Effect<void>;
    /** Deletes every note `author` sent and returns them. The room's `lastSeq` does not move. */
    readonly forgetAuthor: (author: UserId) => Effect.Effect<ReadonlyArray<SequencedNote>>;
  }
>()("@billet/backend-pair-room/RoomStore") {}
