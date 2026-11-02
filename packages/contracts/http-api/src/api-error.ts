import { Schema } from "effect";

/** Errors named by the auth, pairing and notes flows in the plan. Each can grow fields later. */
export const ApiError = Schema.TaggedUnion({
  Unauthorized: {},
  /** The request body or a parameter failed validation. */
  InvalidRequest: {},
  /** A dependency is down, so the server refused rather than guess. Safe to retry. */
  Unavailable: {},
  NotFound: {},
  InvalidInvite: {},
  AlreadyPaired: {},
});
export type ApiError = typeof ApiError.Type;
