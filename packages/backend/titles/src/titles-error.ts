import { Data } from "effect";

export class TitleNotFound extends Data.TaggedError("TitleNotFound") {}

/** TMDB asked us to slow down; nothing is asked of it again for `retryAfterSeconds`. */
export class TitlesBusy extends Data.TaggedError("TitlesBusy")<{
  readonly retryAfterSeconds: number;
}> {}

/** TMDB is down, answered something unreadable, or no key is set. `reason` is a fixed label. */
export class TitlesUnavailable extends Data.TaggedError("TitlesUnavailable")<{
  readonly reason: string;
  readonly cause?: unknown;
}> {}
