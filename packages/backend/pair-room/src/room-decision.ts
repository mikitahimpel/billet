import { Schema } from "effect";
import { CatEntry, CatProfile } from "@billet/contracts-domain/cat";
import { CoinEntry, LocalDay } from "@billet/contracts-domain/coins";
import { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";
import {
  ListId,
  ListItemText,
  ListKind,
  ListTitle,
  SharedList,
} from "@billet/contracts-domain/list";
import { MoodCheckIn } from "@billet/contracts-domain/mood";
import { PairId } from "@billet/contracts-domain/pair-id";
import { NoteReaction } from "@billet/contracts-domain/reaction";
import { LoveStreak } from "@billet/contracts-domain/streak";
import {
  CollectionId,
  GiftReward,
  PieceSetId,
  Placement,
  RoomItemId,
} from "@billet/contracts-domain/shop";
import { PresenceState } from "@billet/contracts-realtime/client-message";
import { RiddleWrite } from "./riddle-rules.ts";
import { RoomJoin } from "./room-command.ts";
import { RoomState, SequencedNote } from "./room-state.ts";

/** What an accepted command asks the outside world to do, like an `Output` on the Swift side. */
export const RoomOutput = Schema.TaggedUnion({
  /** `joined` is who claimed the invite, and when, if pairing opened the room. */
  RoomOpened: {
    pairId: PairId,
    joined: Schema.optionalKey(RoomJoin),
  },
  NoteAppended: { entry: SequencedNote, key: IdempotencyKey },
  NoteRepeated: { entry: SequencedNote },
  PresenceChanged: { user: UserId, state: PresenceState },
  /** `adopted` is true for the save that brought the cat home. */
  CatSaved: { cat: CatProfile, by: UserId, adopted: Schema.Boolean },
  /** A journal entry to store: one a phone recorded, or the room's own for a stored note. */
  CatEntryAppended: { entry: CatEntry },
  /** A record whose `id` the room already holds: nothing is stored or fanned out. */
  CatEntryRepeated: { entry: CatEntry },
  /** Inks the pair did not have before, now its own. A grant of inks it had lists none. */
  InksGranted: { inks: Schema.Array(InkId) },
  /** Room pieces the pair did not have before, now its own. */
  ItemsGranted: { items: Schema.Array(RoomItemId) },
  /** The pair's wishlist after a wish, or after a buy took pieces off it. */
  WishlistChanged: { wishlist: Schema.Array(RoomItemId) },
  /** The pair's layout after a change, whole. */
  LayoutChanged: { layout: Schema.Array(Placement) },
  /** A layout change whose `id` the room already applied: nothing changes. */
  LayoutRepeated: {},
  /** A wallet entry to store: coins care earned, or a spend. */
  CoinsEntered: { entry: CoinEntry },
  /** A buy whose `id` the room already holds: nothing is stored or charged again. */
  CoinsRepeated: { entry: CoinEntry },
  ReactionSet: { reaction: NoteReaction },
  /** A reaction the room already holds: nothing is stored or fanned out. */
  ReactionRepeated: { reaction: NoteReaction },
  /** A buy for the Inbox: `items` names the ink, pieces or treat; `offer` a deal or a set. */
  Purchased: {
    id: IdempotencyKey,
    by: UserId,
    at: EpochMillis,
    items: Schema.Array(Schema.String),
    offer: Schema.optionalKey(Schema.String),
    coins: Schema.Int,
  },
  /** The day's free gift, opened by `by`. */
  GiftOpened: { by: UserId, at: EpochMillis, day: LocalDay, reward: GiftReward },
  /** A collection's bonus, paid once. */
  BonusPaid: { by: UserId, at: EpochMillis, collection: CollectionId, coins: Schema.Int },
  /** A list to store whole, made or changed at `at` by the change under `key`. */
  ListSaved: { list: SharedList, key: IdempotencyKey, at: EpochMillis },
  /** A list and its items to delete, by the change under `key` at `at`. */
  ListDeleted: { list: ListId, key: IdempotencyKey, at: EpochMillis },
  /**
   * An Inbox add: `count` items in `at`'s window. `slot` is `by`'s place, so the id names no user.
   */
  ListItemAdded: {
    list: ListId,
    kind: ListKind,
    title: ListTitle,
    by: UserId,
    slot: Schema.Literals([0, 1]),
    at: EpochMillis,
    count: Schema.Int,
    text: ListItemText,
  },
  /**
   * The streak after `by` did their part, or a restore. `lit` is the day it lit, `reached` that
   * day's milestone; `waiting` is the day `by` marked that waits for the partner.
   */
  StreakChanged: {
    streak: LoveStreak,
    by: UserId,
    at: EpochMillis,
    reached: Schema.optionalKey(Schema.Int),
    lit: Schema.optionalKey(LocalDay),
    waiting: Schema.optionalKey(LocalDay),
  },
  /** A member's new check-in, which replaced their last one. */
  MoodSet: { checkIn: MoodCheckIn },
  /** A draw-guess riddle to store, with the try that changed it and the series after it. */
  RiddleSaved: { write: RiddleWrite },
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
  /** A text note in an ink colour the pair has not bought. */
  InkNotOwned: { ink: InkId },
  NotEnoughCoins: { needed: Schema.Int, have: Schema.Int },
  /** A buy of an ink the pair already owns. */
  AlreadyOwned: { ink: InkId },
  /** A buy of an ink the catalog does not sell. */
  NotSold: { ink: InkId },
  /** An order of a piece or a set the pair owns all of already. */
  OfferOwned: { offer: Schema.Union([RoomItemId, PieceSetId]) },
  /** A buy or an order whose price is now above the one the buyer saw. Nothing was charged. */
  PriceChanged: { price: Schema.Int },
  /** An order the catalog does not sell now: an unknown piece, or a featured set out of its week. */
  NotOffered: {},
  /** A reaction to a note the room does not hold. */
  NoteNotFound: {},
  /** A reaction to the reactor's own note. */
  OwnNote: {},
  /** A reaction to a note that is not a photo. */
  NotReactable: {},
  /** Taking back a reaction the room never had. */
  NoReaction: {},
  GiftTaken: { day: LocalDay },
  /** A bonus for a collection with a piece still missing. */
  CollectionIncomplete: { collection: CollectionId },
  BonusTaken: { collection: CollectionId },
  ListNotFound: {},
  ListItemNotFound: {},
  /** A check-in whose note is longer than `moodNoteMaxLength` once trimmed. */
  MoodNoteTooLong: {},
  /** A `GamePlayed` an app sent for a game the room journals itself, such as draw-guess. */
  RoomJournalsGame: {},
  /** A placement the room will not take: the piece is not the pair's, or does not fit. */
  LayoutRefused: {
    reason: Schema.Literals([
      "not-owned",
      "unknown-piece",
      "wrong-surface",
      "outside-room",
      "occupied",
      "last-rest",
    ]),
  },
  /** A restore of a streak that is alive, too short, out for longer than a day, or in cooldown. */
  StreakNotRestorable: {},
});
export type RoomRejection = typeof RoomRejection.Type;

export const RoomDecision = Schema.TaggedUnion({
  /** An accepted command always leaves the room active, so `Vacant` is never persisted. */
  Accepted: { state: RoomState.cases.Active, outputs: Schema.Array(RoomOutput) },
  Rejected: { rejection: RoomRejection },
});
export type RoomDecision = typeof RoomDecision.Type;
