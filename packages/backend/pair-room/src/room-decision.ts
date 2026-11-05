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
import { CollectionId, GiftReward, PieceSetId, RoomItemId } from "@billet/contracts-domain/shop";
import { PresenceState } from "@billet/contracts-realtime/client-message";
import { RoomJoin } from "./room-command.ts";
import { RoomState, SequencedNote } from "./room-state.ts";

/**
 * What an accepted command asks the outside world to do, like an `Output` on the Swift side.
 * `NoteAppended` is stored today. The relay (#17) and push fan-out (#19) read the same outputs.
 * `NoteRepeated` answers a send whose key the room already holds: nothing is stored or fanned out.
 */
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
  /** A wallet entry to store: coins care earned, or a spend. */
  CoinsEntered: { entry: CoinEntry },
  /** A buy whose `id` the room already holds: nothing is stored or charged again. */
  CoinsRepeated: { entry: CoinEntry },
  /** A reaction change to store and fan out. */
  ReactionSet: { reaction: NoteReaction },
  /** A reaction the room already holds: nothing is stored or fanned out. */
  ReactionRepeated: { reaction: NoteReaction },
  /**
   * A buy for the Inbox: what it was for and what it cost. `items` names the ink, the pieces
   * granted or the treat; `offer` is set for a deal or a set.
   */
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
   * An add for the Inbox: `count` items `by` added to the list in the window `at` falls in. `slot`
   * is `by`'s place among the members, so the item's id names no user.
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
  /** A member's new check-in, which replaced their last one. */
  MoodSet: { checkIn: MoodCheckIn },
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
  /** A buy that costs more than the balance. */
  NotEnoughCoins: { needed: Schema.Int, have: Schema.Int },
  /** A buy of an ink the pair already owns. */
  AlreadyOwned: { ink: InkId },
  /** A buy of an ink the catalog does not sell. */
  NotSold: { ink: InkId },
  /** An order of a piece or a set the pair owns all of already. */
  OfferOwned: { offer: Schema.Union([RoomItemId, PieceSetId]) },
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
  /** The day's gift is already open. */
  GiftTaken: { day: LocalDay },
  /** A bonus for a collection with a piece still missing. */
  CollectionIncomplete: { collection: CollectionId },
  /** A bonus already paid. */
  BonusTaken: { collection: CollectionId },
  /** A change to a list the pair no longer has. */
  ListNotFound: {},
  /** A change to an item its list no longer has. */
  ListItemNotFound: {},
  /** A check-in whose note is longer than `moodNoteMaxLength` once trimmed. */
  MoodNoteTooLong: {},
});
export type RoomRejection = typeof RoomRejection.Type;

export const RoomDecision = Schema.TaggedUnion({
  /** An accepted command always leaves the room active, so `Vacant` is never persisted. */
  Accepted: { state: RoomState.cases.Active, outputs: Schema.Array(RoomOutput) },
  Rejected: { rejection: RoomRejection },
});
export type RoomDecision = typeof RoomDecision.Type;
