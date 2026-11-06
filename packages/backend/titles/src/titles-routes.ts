import { Effect, Layer, Schema } from "effect";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { MediaKind, TmdbId } from "@billet/contracts-domain/list";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { routes } from "@billet/contracts-http-api/routes";
import {
  TitleDetails,
  TitleDetailsQuery,
  TitleRecommendationsQuery,
  TitleSearchQuery,
  TitleSearchResponse,
} from "@billet/contracts-http-api/titles";
import { defaultCountry, defaultLanguage, TitleCatalog } from "./title-catalog.ts";
import type { TitleNotFound, TitlesBusy, TitlesUnavailable } from "./titles-error.ts";

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondSearch = HttpServerResponse.schemaJson(TitleSearchResponse);
const respondDetails = HttpServerResponse.schemaJson(TitleDetails);

// The same for both partners and every other caller, but only for signed-in ones, so only the
// phone keeps them. A search is typed again within the hour; where to watch changes daily at most.
const searchHeaders = { "cache-control": "private, max-age=3600" };
const detailsHeaders = { "cache-control": "private, max-age=86400" };

const TitleParams = Schema.Struct({
  kind: MediaKind,
  tmdb: Schema.NumberFromString.pipe(Schema.decodeTo(TmdbId)),
});

/** The seeds of a query that passed `TitleRecommendationsQuery`: `kind:tmdb`, comma-separated. */
const seedsOf = (ids: string) =>
  ids.split(",").map((id) => {
    const [kind, tmdb] = id.split(":");
    return { kind: kind === "tv" ? ("tv" as const) : ("movie" as const), tmdb: Number(tmdb) };
  });

const respondTitleFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | TitleNotFound | TitlesBusy | TitlesUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      TitleNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      TitlesBusy: ({ retryAfterSeconds }) =>
        respondError(ApiError.cases.Unavailable.make({}), {
          status: 429,
          headers: { "cache-control": "no-store", "retry-after": String(retryAfterSeconds) },
        }),
      TitlesUnavailable: ({ reason }) =>
        Effect.logError("titles unavailable", reason).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/** Search and details of films and shows, for any signed-in caller. Needs `TitleCatalog`. */
export const TitlesRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const catalog = yield* TitleCatalog;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.searchTitles.method,
      routes.searchTitles.path,
      Effect.gen(function* () {
        yield* principal;
        const { q, lang } = yield* HttpServerRequest.schemaSearchParams(TitleSearchQuery);
        if (q.trim() === "")
          return yield* respondSearch({ results: [] }, { headers: searchHeaders });
        const found = yield* catalog.search(q, lang ?? defaultLanguage);
        return yield* respondSearch(found, { headers: searchHeaders });
      }).pipe(respondTitleFailures),
    );
    yield* router.add(
      routes.titleRecommendations.method,
      routes.titleRecommendations.path,
      Effect.gen(function* () {
        yield* principal;
        const { ids, lang } =
          yield* HttpServerRequest.schemaSearchParams(TitleRecommendationsQuery);
        const found = yield* catalog.recommendations(seedsOf(ids), lang ?? defaultLanguage);
        return yield* respondSearch(found, { headers: detailsHeaders });
      }).pipe(respondTitleFailures),
    );
    yield* router.add(
      routes.getTitle.method,
      routes.getTitle.path,
      Effect.gen(function* () {
        yield* principal;
        const { kind, tmdb } = yield* HttpRouter.schemaPathParams(TitleParams);
        const { country, lang } = yield* HttpServerRequest.schemaSearchParams(TitleDetailsQuery);
        const details = yield* catalog.details(
          kind,
          tmdb,
          country ?? defaultCountry,
          lang ?? defaultLanguage,
        );
        return yield* respondDetails(details, { headers: detailsHeaders });
      }).pipe(respondTitleFailures),
    );
  }),
).pipe(Layer.orDie);
