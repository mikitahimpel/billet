import { Schema } from "effect";

/** Errors named by the pairing and notes flows in the plan. Each can grow fields later. */
export const ApiError = Schema.TaggedUnion({
  Unauthorized: {},
  NotFound: {},
  InvalidInvite: {},
  AlreadyPaired: {},
});
export type ApiError = typeof ApiError.Type;
