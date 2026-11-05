import { Schema } from "effect";
import { CatEntry, CatProfile } from "@billet/contracts-domain/cat";
import { CoinEntry } from "@billet/contracts-domain/coins";
import { IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PieceSetId, RoomItemId } from "@billet/contracts-domain/shop";
import { NoteReaction } from "@billet/contracts-domain/reaction";
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
});
export type RoomRejection = typeof RoomRejection.Type;

export const RoomDecision = Schema.TaggedUnion({
  /** An accepted command always leaves the room active, so `Vacant` is never persisted. */
  Accepted: { state: RoomState.cases.Active, outputs: Schema.Array(RoomOutput) },
  Rejected: { rejection: RoomRejection },
});
export type RoomDecision = typeof RoomDecision.Type;
