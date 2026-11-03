import { Data } from "effect";

/**
 * A step of deleting the account failed. Whatever was deleted stays deleted, and repeating the
 * request finishes the rest. `reason` is a fixed label.
 */
export class AccountUnavailable extends Data.TaggedError("AccountUnavailable")<{
  readonly reason: string;
}> {}
