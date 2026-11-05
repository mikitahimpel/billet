import { Context, type Effect, type Option } from "effect";
import type { ActivityCursor } from "@billet/contracts-domain/activity";
import type { CatEntry } from "@billet/contracts-domain/cat";
import type { CoinEntry, CoinEntryId } from "@billet/contracts-domain/coins";
import type { ActivityRow } from "./activity.ts";
import type { EpochMillis, IdempotencyKey, NoteId, UserId } from "@billet/contracts-domain/ids";
import type { NoteReaction } from "@billet/contracts-domain/reaction";
import type { ActiveRoom, RoomState, SequencedNote } from "./room-state.ts";

/** A note to store, with the key its author sent it under. */
export type AppendedNote = { readonly entry: SequencedNote; readonly key: IdempotencyKey };

/** A room's durable storage. Failures are defects: the room cannot act without its storage. */
export class RoomStore extends Context.Service<
  RoomStore,
  {
    readonly load: Effect.Effect<RoomState>;
    /**
     * Saves the state and the cat, appends the notes, journal and wallet entries, and writes the
     * activity rows and reactions over any with the same id, as one atomic write. Rows older than the retention
     * are pruned in the same write.
     */
    readonly commit: (
      room: ActiveRoom,
      notes: ReadonlyArray<AppendedNote>,
      catEntries: ReadonlyArray<CatEntry>,
      activity: ReadonlyArray<ActivityRow>,
      coins: ReadonlyArray<CoinEntry>,
      reactions: ReadonlyArray<NoteReaction>,
    ) => Effect.Effect<void>;
    /** The stored note with this id, if the room still holds it. */
    readonly noteById: (id: NoteId) => Effect.Effect<Option.Option<SequencedNote>>;
    /** `by`'s reaction to `note`, taken back or not, if they ever reacted. */
    readonly reactionOf: (note: NoteId, by: UserId) => Effect.Effect<Option.Option<NoteReaction>>;
    /** Reactions changed after `afterRev`, oldest change first. */
    readonly reactionsAfter: (
      afterRev: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<NoteReaction>>;
    /** Deletes every reaction: the pair is ending. */
    readonly forgetReactions: Effect.Effect<void>;
    /** Deletes both members' check-ins: the pair is ending. */
    readonly forgetMoods: Effect.Effect<void>;
    /** The wallet entry stored under `id`, if any. */
    readonly coinEntryById: (id: CoinEntryId) => Effect.Effect<Option.Option<CoinEntry>>;
    /**
     * Wallet entries stored after the one under `after` (from the first when absent), oldest
     * first. An `after` the store does not hold reads from the first.
     */
    readonly coinEntriesAfter: (
      after: CoinEntryId | undefined,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<CoinEntry>>;
    /** Activity rows below `before` (all of them when absent), newest first. */
    readonly activityBefore: (
      before: ActivityCursor | undefined,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<ActivityRow>>;
    /** How many rows above `mark` (all, when absent) `user` did not make themselves. */
    readonly unreadCount: (user: UserId, mark: ActivityCursor | undefined) => Effect.Effect<number>;
    readonly readMark: (user: UserId) => Effect.Effect<Option.Option<ActivityCursor>>;
    readonly saveReadMark: (user: UserId, mark: ActivityCursor) => Effect.Effect<void>;
    /** Deletes every activity row and both read marks: the pair is ending. */
    readonly forgetActivity: Effect.Effect<void>;
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
