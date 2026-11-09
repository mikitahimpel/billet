import { Data } from "effect";

/** Whatever was deleted stays deleted; repeating the request finishes the rest. */
export class AccountUnavailable extends Data.TaggedError("AccountUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}
