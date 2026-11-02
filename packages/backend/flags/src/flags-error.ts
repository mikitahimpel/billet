import { Data } from "effect";

/** A dependency failed. The client keeps its stored flags or its defaults; `reason` is a fixed label. */
export class FlagsUnavailable extends Data.TaggedError("FlagsUnavailable")<{
  readonly reason: string;
}> {}
