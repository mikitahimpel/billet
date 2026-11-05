import { Context, type Effect } from "effect";
import type { ActivityCursor } from "@billet/contracts-domain/activity";
import type { CatEntry, NatureSeed } from "@billet/contracts-domain/cat";
import type { ActivityResponse } from "@billet/contracts-http-api/activity";
import type { CoinEntryId, EarnEvent } from "@billet/contracts-domain/coins";
import type { IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import type { InkId } from "@billet/contracts-domain/inks";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { CollectionId, RoomItemId, ShopOffer } from "@billet/contracts-domain/shop";
import type {
  CatResponse,
  RecordCatEventRequest,
  SaveCatRequest,
} from "@billet/contracts-http-api/cat";
import type { CoinsResponse } from "@billet/contracts-http-api/coins";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import type { ShopResponse } from "@billet/contracts-http-api/shop";
import type { ReactRequest } from "@billet/contracts-http-api/reaction";
import type { NoteReaction } from "@billet/contracts-domain/reaction";
import type { MoodCheckIn } from "@billet/contracts-domain/mood";
import type { SetMoodRequest } from "@billet/contracts-http-api/mood";
import type { GiftCommand, GiftsResult } from "@billet/backend-pair-room/gifts";
import type { RoomJoin } from "@billet/backend-pair-room/room-command";
import type { RoomDecision } from "@billet/backend-pair-room/room-decision";
import type { SequencedNote } from "@billet/backend-pair-room/room-state";
import type { NotesUnavailable } from "./notes-error.ts";

/** Reaches the `PairRoom` of a couple. Failing to reach it is `NotesUnavailable`. */
export class PairRooms extends Context.Service<
  PairRooms,
  {
    /** `joined` is who claimed the invite, and when: pairing passes it, a lazy open does not. */
    readonly open: (
      pairId: PairId,
      members: readonly [UserId, UserId],
      joined?: RoomJoin,
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
    /**
     * The pair's balance and wallet entries after `after`, oldest first, or null while the room is
     * not open. A room owed its welcome coins gets them first.
     */
    readonly coins: (
      pairId: PairId,
      after: CoinEntryId | undefined,
      limit: number,
    ) => Effect.Effect<CoinsResponse | null, NotesUnavailable>;
    /** Buys one ink with the pair's coins, once per `id`. */
    readonly buy: (
      pairId: PairId,
      by: UserId,
      id: IdempotencyKey,
      ink: InkId,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    /**
     * What the pair has: balance, inks, room pieces and wishlist, or null while the room is not
     * open. A room owed its welcome coins gets them first.
     */
    readonly shop: (pairId: PairId) => Effect.Effect<ShopResponse | null, NotesUnavailable>;
    /**
     * Buys one offer with the pair's coins, once per `id`, on the local day `utcOffsetSeconds`
     * from UTC (absent: the cat's, else UTC).
     */
    readonly order: (
      pairId: PairId,
      by: UserId,
      id: IdempotencyKey,
      offer: ShopOffer,
      utcOffsetSeconds?: number,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    /** Opens the pair's gift of the local day, once a day for the pair. */
    readonly openGift: (
      pairId: PairId,
      by: UserId,
      utcOffsetSeconds: number | undefined,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    /** Collects a complete collection's bonus, once. */
    readonly claimBonus: (
      pairId: PairId,
      by: UserId,
      collection: CollectionId,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    /** Pays something the couple did in the app, once per ref and within the day's cap. */
    readonly earn: (
      pairId: PairId,
      by: UserId,
      event: EarnEvent,
      utcOffsetSeconds: number | undefined,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    readonly setWish: (
      pairId: PairId,
      by: UserId,
      item: RoomItemId,
      wished: boolean,
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
    /** Closes the room's open sockets, as the pair has ended. Safe to repeat. */
    readonly endSessions: (pairId: PairId) => Effect.Effect<void, NotesUnavailable>;
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
    /** One page of the Inbox as `caller` sees it. A room not opened yet has none. */
    readonly activity: (
      pairId: PairId,
      caller: UserId,
      before: ActivityCursor | undefined,
      limit: number,
    ) => Effect.Effect<ActivityResponse, NotesUnavailable>;
    /** Sets or takes back `by`'s reaction to one of the partner's photos. */
    readonly react: (
      pairId: PairId,
      by: UserId,
      request: ReactRequest,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    /** Reaction changes with `rev` above `afterRev`, oldest first. */
    readonly reactions: (
      pairId: PairId,
      afterRev: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<NoteReaction>, NotesUnavailable>;
    /** Replaces `by`'s check-in with how they feel now. */
    readonly setMood: (
      pairId: PairId,
      by: UserId,
      request: SetMoodRequest,
    ) => Effect.Effect<RoomDecision, NotesUnavailable>;
    /** Each member's latest check-in. A room not opened yet has none. */
    readonly moods: (pairId: PairId) => Effect.Effect<ReadonlyArray<MoodCheckIn>, NotesUnavailable>;
    /** Runs one gift command for `by`: see `GiftsRoom`. */
    readonly gifts: (
      pairId: PairId,
      by: UserId,
      command: GiftCommand,
    ) => Effect.Effect<GiftsResult, NotesUnavailable>;
    /** Moves `user`'s read mark up to `upTo` and answers their unread count. */
    readonly markActivityRead: (
      pairId: PairId,
      user: UserId,
      upTo: ActivityCursor,
    ) => Effect.Effect<number, NotesUnavailable>;
  }
>()("@billet/backend-notes/PairRooms") {}
