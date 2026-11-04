import { Data } from "effect";

/**
 * The caller is not who it claims to be. `reason` is a fixed label for logs, never token or claim
 * content, and it stays on the server: every rejection looks the same to the client.
 */
export class AuthRejected extends Data.TaggedError("AuthRejected")<{
  readonly reason: string;
}> {}

/** A dependency failed, so nothing was granted. The client can retry; `reason` is a fixed label. */
export class AuthUnavailable extends Data.TaggedError("AuthUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}

/** The Apple ID is already linked to another account, so it can't be linked to the caller's. */
export class AppleIdInUse extends Data.TaggedError("AppleIdInUse")<{}> {}
