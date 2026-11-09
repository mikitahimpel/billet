import { Context, type Effect } from "effect";
import type { TitleNotFound, TitlesBusy, TitlesUnavailable } from "./titles-error.ts";

/**
 * `path` is under `/3`; `params` never carry the key. A 429 is `TitlesBusy` with `Retry-After`.
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
