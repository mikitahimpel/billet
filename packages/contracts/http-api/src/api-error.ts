import { Schema } from "effect";
import { LocalDay } from "@billet/contracts-domain/coins";
import { InkId } from "@billet/contracts-domain/inks";
import { CollectionId } from "@billet/contracts-domain/shop";

/** Errors named by the auth, pairing, notes and payments flows. Each can grow fields later. */
export const ApiError = Schema.TaggedUnion({
  Unauthorized: {},
  /** The request body or a parameter failed validation. */
  InvalidRequest: {},
  /** A dependency is down, so the server refused rather than guess. Safe to retry. */
  Unavailable: {},
  NotFound: {},
  InvalidInvite: {},
  AlreadyPaired: {},
  /** This Apple ID is already linked to another account, so it can't be linked to the caller's. */
  AppleIdInUse: {},
  /** Bad signature/chain, foreign bundle, refused environment or non-coin product. Final. */
  InvalidPurchase: {},
  /** A text note in an ink colour the pair has not bought. Buy it in the shop, or use another. */
  InkNotOwned: { ink: InkId },
  NotEnoughCoins: {
    needed: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
    have: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
  },
  AlreadyOwned: { itemId: Schema.String },
  /** A piece the pair does not own, does not fit where it was put, or is not placed that way. */
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
  CollectionIncomplete: { collection: CollectionId },
  /** The day's gift is already open. Come back tomorrow. */
  GiftTaken: { day: LocalDay },
  /** A collection's bonus already paid. */
  BonusTaken: { collection: CollectionId },
  /** Server price is above `expectedPrice`, nothing charged. Show `price` (now) and ask again. */
  PriceChanged: { price: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)) },
  /** A buy for the cat, such as a treat, before the couple adopted one. */
  CatNotAdopted: {},
  /** A restore of a streak that is alive, too short, out for longer than a day, or in cooldown. */
  StreakNotRestorable: {},
});
export type ApiError = typeof ApiError.Type;
