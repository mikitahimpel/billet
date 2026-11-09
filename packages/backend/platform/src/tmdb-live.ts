import { Effect, Layer } from "effect";
import { Tmdb } from "@billet/backend-titles/tmdb";
import { TmdbStub } from "@billet/backend-titles/tmdb-stub";
import { TitleNotFound, TitlesBusy, TitlesUnavailable } from "@billet/backend-titles/titles-error";
import { spanMethods } from "@billet/backend-observability/span-methods";

const origin = "https://api.themoviedb.org/3";

/** TMDB's `Retry-After` in seconds, kept between 1 second and an hour. */
const retryAfterOf = (header: string | null): number => {
  const seconds = Number(header);
  return Number.isFinite(seconds) ? Math.min(3600, Math.max(1, Math.ceil(seconds))) : 10;
};

/**
 * The token goes in a header, never a URL. No failure body is kept: it may quote the request.
 */
export const TmdbLive = (token: string, fetcher: typeof fetch = fetch): Layer.Layer<Tmdb> =>
  Layer.succeed(
    Tmdb,
    Tmdb.of(
      spanMethods("Tmdb", {
        get: (path, params) =>
          Effect.gen(function* () {
            const url = `${origin}${path}?${new URLSearchParams(params).toString()}`;
            const response = yield* Effect.tryPromise({
              try: () =>
                fetcher(url, {
                  headers: { authorization: `Bearer ${token}`, accept: "application/json" },
                }),
              catch: () => new TitlesUnavailable({ reason: "tmdb-unreachable" }),
            });
            if (response.status === 404) return yield* new TitleNotFound();
            if (response.status === 429) {
              return yield* new TitlesBusy({
                retryAfterSeconds: retryAfterOf(response.headers.get("retry-after")),
              });
            }
            if (!response.ok) {
              return yield* new TitlesUnavailable({ reason: `tmdb-status-${response.status}` });
            }
            return yield* Effect.tryPromise({
              try: () => response.text(),
              catch: () => new TitlesUnavailable({ reason: "tmdb-unreachable" }),
            });
          }),
      }),
    ),
  );

const TmdbMissing: Layer.Layer<Tmdb> = Layer.succeed(
  Tmdb,
  Tmdb.of({ get: () => Effect.fail(new TitlesUnavailable({ reason: "tmdb-token-missing" })) }),
);

/** Without a token, `prod` answers 503 and every other stage answers from `TmdbStub`. */
export const tmdbFor = (token: string | undefined, stage: string | undefined): Layer.Layer<Tmdb> =>
  token !== undefined && token !== "" ? TmdbLive(token) : stage === "prod" ? TmdbMissing : TmdbStub;
