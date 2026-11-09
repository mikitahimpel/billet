import { Data } from "effect";

/** `reason` is a fixed log label that stays on the server: every rejection looks the same. */
export class AuthRejected extends Data.TaggedError("AuthRejected")<{
  readonly reason: string;
}> {}

/** A dependency failed, so nothing was granted. The client can retry; `reason` is a fixed label. */
export class AuthUnavailable extends Data.TaggedError("AuthUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}

export class AppleIdInUse extends Data.TaggedError("AppleIdInUse")<{}> {}
