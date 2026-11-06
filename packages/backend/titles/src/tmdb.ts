import { Context, type Effect } from "effect";
import type { TitleNotFound, TitlesBusy, TitlesUnavailable } from "./titles-error.ts";

/**
 * TMDB's API v3, signed with the Worker's key. `path` is under `/3`, such as `/search/multi`;
 * `params` never carry the key. Answers the body as TMDB sent it. A 404 is `TitleNotFound`, a 429
 * `TitlesBusy` with TMDB's `Retry-After`, and anything else not 2xx `TitlesUnavailable`.
 */
export class Tmdb extends Context.Service<
  Tmdb,
  {
    readonly get: (
      path: string,
      params: Readonly<Record<string, string>>,
    ) => Effect.Effect<string, TitleNotFound | TitlesBusy | TitlesUnavailable>;
  }
>()("@billet/backend-titles/Tmdb") {}
