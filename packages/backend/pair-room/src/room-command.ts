import { Schema } from "effect";
import {
  CatEvent,
  CatLook,
  CatName,
  NatureSeed,
  UtcOffsetSeconds,
} from "@billet/contracts-domain/cat";
import { CoinEntryId, EarnEvent } from "@billet/contracts-domain/coins";
import { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";
import { Note } from "@billet/contracts-domain/note";
import { NoteReaction, Reaction } from "@billet/contracts-domain/reaction";
import { PairId } from "@billet/contracts-domain/pair-id";
import { CollectionId, RoomItemId, ShopOffer } from "@billet/contracts-domain/shop";
import { PresenceState } from "@billet/contracts-realtime/client-message";

/** Who claimed the invite, and when. */
export const RoomJoin = Schema.Struct({ user: UserId, at: EpochMillis });
export type RoomJoin = typeof RoomJoin.Type;

/** Everything that can change a room. Ids and times are settled before a command reaches `decide`. */
export const RoomCommand = Schema.TaggedUnion({
  /** `joined` is who claimed the invite, and when: present when pairing opens the room. */
  Open: {
    pairId: PairId,
    members: Schema.Tuple([UserId, UserId]),
    joined: Schema.optionalKey(RoomJoin),
  },
  SendNote: { note: Note, key: IdempotencyKey },
  SetPresence: { user: UserId, state: PresenceState },
  /**
   * Sets `by`'s reaction to `note`, or takes it back when `reaction` is absent. `current` is the
   * reaction the room holds for them on that note, if any.
   */
  React: {
    by: UserId,
    note: Note,
    current: Schema.optionalKey(NoteReaction),
    reaction: Schema.optionalKey(Reaction),
    at: EpochMillis,
  },
  /** Adopts the cat, or renames it. `natureSeed` and `at` are used only by an adoption. */
  SaveCat: {
    user: UserId,
    name: CatName,
    look: CatLook,
    utcOffsetSeconds: UtcOffsetSeconds,
    natureSeed: NatureSeed,
    at: EpochMillis,
  },
  RecordCatEvent: { id: IdempotencyKey, by: UserId, at: EpochMillis, event: CatEvent },
  /** Gives the pair ink colours, as the wallet does once it has taken their coins. */
  GrantInks: { inks: Schema.Array(InkId) },
  /** Buys one ink with the pair's coins, at its catalog price. `id` is the buyer's, once. */
  Buy: { id: IdempotencyKey, by: UserId, ink: InkId, at: EpochMillis },
  /**
   * Buys one offer with the pair's coins, at the catalog's price: a piece at its deal price when it
   * is a deal of the pair's local day, counted `utcOffsetSeconds` from UTC (else the cat's clock,
   * else UTC). `id` is the buyer's, once.
   */
  Order: {
    id: IdempotencyKey,
    by: UserId,
    offer: ShopOffer,
    at: EpochMillis,
    utcOffsetSeconds: Schema.optionalKey(UtcOffsetSeconds),
  },
  SetWish: { by: UserId, item: RoomItemId, wished: Schema.Boolean },
  /** Gives the pair its welcome coins, once: the room service sends it after an open. */
  Welcome: { at: EpochMillis },
  /** Opens the pair's free gift of the local day, once a day for the pair. */
  OpenGift: { by: UserId, at: EpochMillis, utcOffsetSeconds: UtcOffsetSeconds },
  /** Collects a collection's bonus, once ever, when the pair owns every piece. */
  ClaimBonus: { by: UserId, at: EpochMillis, collection: CollectionId },
  /** Pays something the couple did in the app, within its daily cap and once per ref. */
  Earn: { by: UserId, at: EpochMillis, utcOffsetSeconds: UtcOffsetSeconds, event: EarnEvent },
  /**
   * Coins bought with money: `buy` pays `coins` in, `refund` takes them back. `id` is the payments
   * ledger's entry id, written once; `ref` is the pack.
   */
  CreditPurchase: {
    id: CoinEntryId,
    kind: Schema.Literals(["buy", "refund"]),
    coins: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
    ref: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(100)),
    at: EpochMillis,
  },
});
export type RoomCommand = typeof RoomCommand.Type;
