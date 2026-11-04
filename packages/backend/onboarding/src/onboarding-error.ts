import { Data } from "effect";

/** The answer doesn't fit the current catalogue. The client drops it; `reason` is a fixed label. */
export class InvalidAnswer extends Data.TaggedError("InvalidAnswer")<{
  readonly reason: string;
}> {}

/** Storage failed. The client keeps the answer queued and retries; `reason` is a fixed label. */
export class OnboardingUnavailable extends Data.TaggedError("OnboardingUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}
