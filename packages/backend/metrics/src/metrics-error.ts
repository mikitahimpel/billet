import { Data } from "effect";

/** Storage failed. `reason` is a fixed label; nothing from the storage error survives. */
export class MetricsUnavailable extends Data.TaggedError("MetricsUnavailable")<{
  readonly reason: string;
}> {}
