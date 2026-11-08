import { Data } from "effect";

/** A dependency failed, so nothing changed. The caller can retry; `reason` is a fixed label. */
export class ReviewUnavailable extends Data.TaggedError("ReviewUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}
