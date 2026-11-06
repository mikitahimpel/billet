import { Clock, Context, Effect, Layer, Option, Schema } from "effect";
import {
  type CountryCode,
  type MediaKind,
  ReleaseYear,
  TmdbImagePath,
} from "@billet/contracts-domain/list";
import {
  TitleDetails,
  TitleSummary,
  type TitleSearchResponse,
  type WatchProvider,
} from "@billet/contracts-http-api/titles";
import { TitleCache } from "./title-cache.ts";
import { TitleNotFound, TitlesBusy, TitlesUnavailable } from "./titles-error.ts";
import { Tmdb } from "./tmdb.ts";

type Failure = TitleNotFound | TitlesBusy | TitlesUnavailable;

const day = 86_400;
// TMDB allows keeping an answer for six months. New releases change a search and JustWatch
// changes where to watch, so both are kept far less.
export const searchTtlSeconds = day;
export const detailsTtlSeconds = 7 * day;
export const recommendationsTtlSeconds = 7 * day;

/** The most titles one ask for recommendations answers. */
const maxRecommendations = 20;

/** Holds the instant, in epoch milliseconds, before which TMDB is not asked anything. */
export const pauseKey = "tmdb:pause";

/** The first results of a search are shown with a runtime or a season count, from their details. */
const detailedResults = 8;

/** Where to watch is per country; a caller that names none gets this one's. */
export const defaultCountry = "US";
export const defaultLanguage = "en";

/**
 * Films and shows from TMDB, as the app shows them. Every TMDB answer goes through `TitleCache`;
 * once TMDB answers 429, nothing is asked of it until its `Retry-After` has passed, while answers
 * already cached are still served.
 */
export class TitleCatalog extends Context.Service<
  TitleCatalog,
  {
    readonly search: (
      query: string,
      language: string,
    ) => Effect.Effect<TitleSearchResponse, TitlesBusy | TitlesUnavailable>;
    readonly details: (
      kind: MediaKind,
      tmdb: number,
      country: CountryCode,
      language: string,
    ) => Effect.Effect<TitleDetails, Failure>;
    /**
     * Titles TMDB recommends for those who liked `seeds`, taken in turn from each seed's list,
     * without repeats or the seeds themselves. A seed TMDB lacks adds nothing.
     */
    readonly recommendations: (
      seeds: ReadonlyArray<{ readonly kind: MediaKind; readonly tmdb: number }>,
      language: string,
    ) => Effect.Effect<TitleSearchResponse, TitlesBusy | TitlesUnavailable>;
  }
>()("@billet/backend-titles/TitleCatalog") {
  static readonly layer: Layer.Layer<TitleCatalog, never, Tmdb | TitleCache> = Layer.effect(
    TitleCatalog,
    Effect.gen(function* () {
      const tmdb = yield* Tmdb;
      const cache = yield* TitleCache;

      const fetchJson = (
        path: string,
        params: Readonly<Record<string, string>>,
        ttlSeconds: number,
      ): Effect.Effect<unknown, Failure> =>
        Effect.gen(function* () {
          const query = new URLSearchParams(Object.entries(params).toSorted()).toString();
          const key = `tmdb:${path}?${query}`;
          const hit = yield* cache.get(key);
          if (Option.isSome(hit)) return yield* parse(hit.value);

          const now = yield* Clock.currentTimeMillis;
          const until = Option.match(yield* cache.get(pauseKey), {
            onNone: () => 0,
            onSome: Number,
          });
          if (until > now) {
            return yield* new TitlesBusy({ retryAfterSeconds: Math.ceil((until - now) / 1000) });
          }

          const body = yield* tmdb
            .get(path, params)
            .pipe(
              Effect.tapError((error) =>
                error._tag === "TitlesBusy"
                  ? cache.put(
                      pauseKey,
                      String(now + error.retryAfterSeconds * 1000),
                      error.retryAfterSeconds,
                    )
                  : Effect.void,
              ),
            );
          const json = yield* parse(body);
          yield* cache.put(key, body, ttlSeconds);
          return json;
        });

      const rawDetails = (kind: MediaKind, id: number, language: string) =>
        fetchJson(
          `/${kind}/${id}`,
          { language, append_to_response: "watch/providers" },
          detailsTtlSeconds,
        );

      const withLength = (title: TitleSummary, language: string) =>
        rawDetails(title.kind, title.tmdb, language).pipe(
          Effect.map((raw) => ({ ...title, ...lengthOf(title.kind, record(raw)) })),
          Effect.orElseSucceed(() => title),
        );

      return TitleCatalog.of({
        search: (query, language) =>
          Effect.gen(function* () {
            const raw = yield* fetchJson(
              "/search/multi",
              {
                query: query.trim().replace(/\s+/g, " ").toLowerCase(),
                language,
                include_adult: "false",
                page: "1",
              },
              searchTtlSeconds,
            ).pipe(Effect.catchTag("TitleNotFound", () => Effect.succeed({})));
            const found = list(record(raw)["results"]).flatMap((entry) => {
              const result = record(entry);
              const kind = result["media_type"];
              return kind === "movie" || kind === "tv"
                ? Option.toArray(summaryOf(kind, result))
                : [];
            });
            const detailed = yield* Effect.forEach(
              found.slice(0, detailedResults),
              (title) => withLength(title, language),
              { concurrency: detailedResults },
            );
            return { results: [...detailed, ...found.slice(detailedResults)] };
          }),
        details: (kind, id, country, language) =>
          Effect.gen(function* () {
            const raw = record(yield* rawDetails(kind, id, language));
            const summary = Option.getOrUndefined(summaryOf(kind, raw));
            if (summary === undefined) {
              return yield* new TitlesUnavailable({ reason: "tmdb-unreadable" });
            }
            const decoded = decodeDetails({
              ...summary,
              ...lengthOf(kind, raw),
              ...present({ backdropPath: image(raw["backdrop_path"]) }),
              overview: text(raw["overview"]) ?? "",
              genres: list(raw["genres"]).flatMap((genre) => {
                const name = text(record(genre)["name"]);
                return name === undefined ? [] : [name];
              }),
              watch: watchOf(record(record(raw["watch/providers"])["results"])[country], country),
            });
            return yield* Option.match(decoded, {
              onNone: () => Effect.fail(new TitlesUnavailable({ reason: "tmdb-unreadable" })),
              onSome: Effect.succeed,
            });
          }),
        recommendations: (seeds, language) =>
          Effect.gen(function* () {
            const lists = yield* Effect.forEach(
              seeds,
              (seed) =>
                fetchJson(
                  `/${seed.kind}/${seed.tmdb}/recommendations`,
                  { language, page: "1" },
                  recommendationsTtlSeconds,
                ).pipe(
                  Effect.map((raw) =>
                    list(record(raw)["results"]).flatMap((entry) => {
                      const result = record(entry);
                      const kind = result["media_type"] ?? seed.kind;
                      return kind === "movie" || kind === "tv"
                        ? Option.toArray(summaryOf(kind, result))
                        : [];
                    }),
                  ),
                  Effect.catchTag("TitleNotFound", () => Effect.succeed([])),
                ),
              { concurrency: seeds.length },
            );
            const seen = new Set(seeds.map((seed) => `${seed.kind}:${seed.tmdb}`));
            const results: Array<TitleSummary> = [];
            const longest = Math.max(0, ...lists.map((found) => found.length));
            for (let at = 0; at < longest && results.length < maxRecommendations; at += 1) {
              for (const found of lists) {
                const title = found[at];
                if (title === undefined || seen.has(`${title.kind}:${title.tmdb}`)) continue;
                seen.add(`${title.kind}:${title.tmdb}`);
                results.push(title);
              }
            }
            return { results: results.slice(0, maxRecommendations) };
          }),
      });
    }),
  );
}

const parse = (body: string) =>
  Effect.try({
    try: (): unknown => JSON.parse(body),
    catch: (cause) => new TitlesUnavailable({ reason: "tmdb-unreadable", cause }),
  });

const decodeSummary = Schema.decodeUnknownOption(TitleSummary);
const decodeDetails = Schema.decodeUnknownOption(TitleDetails);
const isImage = Schema.is(TmdbImagePath);
const isYear = Schema.is(ReleaseYear);

// TMDB's JSON is read field by field, so one odd field drops that field and not the title.
const record = (value: unknown): Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
const list = (value: unknown): ReadonlyArray<unknown> => (Array.isArray(value) ? value : []);
const text = (value: unknown): string | undefined =>
  typeof value === "string" && value.trim() !== "" ? value.trim() : undefined;
const count = (value: unknown): number | undefined =>
  typeof value === "number" && Number.isInteger(value) && value >= 1 ? value : undefined;
const image = (value: unknown): string | undefined => (isImage(value) ? value : undefined);
const yearOf = (date: unknown): number | undefined => {
  const year = Number(text(date)?.slice(0, 4));
  return isYear(year) ? year : undefined;
};
/** TMDB scores an unrated title 0, which is no score at all. */
const ratingOf = (average: unknown, votes: unknown): number | undefined =>
  typeof average === "number" && average > 0 && average <= 10 && count(votes) !== undefined
    ? Math.round(average * 10) / 10
    : undefined;

/** The fields that are not `undefined`, so an optional key is left out rather than set. */
const present = <T extends Record<string, unknown>>(fields: T) =>
  Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== undefined));

const summaryOf = (
  kind: MediaKind,
  raw: Readonly<Record<string, unknown>>,
): Option.Option<TitleSummary> =>
  decodeSummary({
    kind,
    tmdb: raw["id"],
    title: text(kind === "movie" ? raw["title"] : raw["name"]),
    ...present({
      year: yearOf(kind === "movie" ? raw["release_date"] : raw["first_air_date"]),
      posterPath: image(raw["poster_path"]),
      rating: ratingOf(raw["vote_average"], raw["vote_count"]),
    }),
  });

const lengthOf = (kind: MediaKind, raw: Readonly<Record<string, unknown>>) =>
  present(
    kind === "movie"
      ? { runtime: count(raw["runtime"]) }
      : { seasons: count(raw["number_of_seasons"]) },
  );

const providersOf = (value: unknown): ReadonlyArray<WatchProvider> =>
  list(value).flatMap((entry) => {
    const provider = record(entry);
    const id = count(provider["provider_id"]);
    const name = text(provider["provider_name"]);
    if (id === undefined || name === undefined) return [];
    const logoPath = image(provider["logo_path"]);
    return [logoPath === undefined ? { id, name } : { id, name, logoPath }];
  });

const watchOf = (value: unknown, country: CountryCode) => {
  const options = record(value);
  const stream = providersOf(options["flatrate"]);
  // A shop often both rents and sells a title, and is named once.
  const seen = new Set(stream.map((provider) => provider.id));
  const rentOrBuy = [...providersOf(options["rent"]), ...providersOf(options["buy"])].filter(
    (provider) => {
      if (seen.has(provider.id)) return false;
      seen.add(provider.id);
      return true;
    },
  );
  return { country, ...present({ link: text(options["link"]) }), stream, rentOrBuy };
};
