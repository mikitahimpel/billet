import { Schema } from "effect";
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
  /**
   * An App Store transaction or notification that can't be honoured: a bad signature or
   * certificate chain, another app's bundle, an environment this stage doesn't accept, or a
   * product that isn't a coin pack. Retrying the same one fails the same way.
   */
  InvalidPurchase: {},
  /** A text note in an ink colour the pair has not bought. Buy it in the shop, or use another. */
  InkNotOwned: { ink: InkId },
  /** A buy that costs more than the pair's balance. */
  NotEnoughCoins: {
    needed: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
    have: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
  },
  /** A buy of an item the pair already owns. */
  AlreadyOwned: { itemId: Schema.String },
  /** A bonus for a collection with a piece still missing. */
  CollectionIncomplete: { collection: CollectionId },
  /** A buy for the cat, such as a treat, before the couple adopted one. */
  CatNotAdopted: {},
});
export type ApiError = typeof ApiError.Type;
