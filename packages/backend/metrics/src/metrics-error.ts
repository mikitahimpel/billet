import { Data } from "effect";

/** Storage failed. `reason` is a fixed label; nothing from the storage error survives. */
export class MetricsUnavailable extends Data.TaggedError("MetricsUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}
