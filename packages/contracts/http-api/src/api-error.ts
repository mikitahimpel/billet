import { Schema } from "effect";

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
});
export type ApiError = typeof ApiError.Type;
