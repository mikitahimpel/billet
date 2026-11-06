import { Schema } from "effect";
import {
  CountryCode,
  MediaKind,
  ReleaseYear,
  TmdbId,
  TmdbImagePath,
} from "@billet/contracts-domain/list";

const Count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(1));

/** TMDB's audience score, 0 to 10. */
const Rating = Schema.Number.check(Schema.isBetween({ minimum: 0, maximum: 10 }));

/** A film or a show as search shows it. `runtime` is minutes, for a film; `seasons` for a show. */
export const TitleSummary = Schema.Struct({
  kind: MediaKind,
  tmdb: TmdbId,
  title: Schema.String,
  year: Schema.optionalKey(ReleaseYear),
  posterPath: Schema.optionalKey(TmdbImagePath),
  rating: Schema.optionalKey(Rating),
  runtime: Schema.optionalKey(Count),
  seasons: Schema.optionalKey(Count),
});
export type TitleSummary = typeof TitleSummary.Type;

/** `GET /v1/titles/search?q=&lang=`: the best matches first, films and shows only. */
export const TitleSearchResponse = Schema.Struct({ results: Schema.Array(TitleSummary) });
export type TitleSearchResponse = typeof TitleSearchResponse.Type;

/** A streaming service, a shop or a rental, as JustWatch names it. */
export const WatchProvider = Schema.Struct({
  id: TmdbId,
  name: Schema.String,
  logoPath: Schema.optionalKey(TmdbImagePath),
});
export type WatchProvider = typeof WatchProvider.Type;

/**
 * Where the title can be watched in `country`, from JustWatch through TMDB. `stream` is included in
 * a subscription; `rentOrBuy` costs extra. `link` is TMDB's page that lists them.
 */
export const WatchOptions = Schema.Struct({
  country: CountryCode,
  link: Schema.optionalKey(Schema.String),
  stream: Schema.Array(WatchProvider),
  rentOrBuy: Schema.Array(WatchProvider),
});
export type WatchOptions = typeof WatchOptions.Type;

/** `GET /v1/titles/:kind/:tmdb?country=&lang=`: the card's details. */
export const TitleDetails = Schema.Struct({
  ...TitleSummary.fields,
  backdropPath: Schema.optionalKey(TmdbImagePath),
  overview: Schema.String,
  genres: Schema.Array(Schema.String),
  watch: WatchOptions,
});
export type TitleDetails = typeof TitleDetails.Type;

/** A BCP 47 tag TMDB takes, such as `en` or `pt-BR`. */
export const TitleLanguage = Schema.String.check(Schema.isPattern(/^[a-z]{2}(-[A-Z]{2})?$/));

export const TitleSearchQuery = Schema.Struct({
  q: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(100)),
  lang: Schema.optionalKey(TitleLanguage),
});
export type TitleSearchQuery = typeof TitleSearchQuery.Type;

export const TitleDetailsQuery = Schema.Struct({
  country: Schema.optionalKey(CountryCode),
  lang: Schema.optionalKey(TitleLanguage),
});
export type TitleDetailsQuery = typeof TitleDetailsQuery.Type;

/** At most this many titles are asked for recommendations at once. */
export const maxRecommendationSeeds = 5;

/**
 * `GET /v1/titles/recommendations?ids=&lang=`: `ids` is 1 to `maxRecommendationSeeds` titles as
 * `kind:tmdb`, comma-separated, such as `movie:329865,tv:95396`. Answers a `TitleSearchResponse`.
 */
export const TitleRecommendationsQuery = Schema.Struct({
  ids: Schema.String.check(
    Schema.isPattern(/^(movie|tv):[1-9][0-9]{0,9}(,(movie|tv):[1-9][0-9]{0,9}){0,4}$/),
  ),
  lang: Schema.optionalKey(TitleLanguage),
});
export type TitleRecommendationsQuery = typeof TitleRecommendationsQuery.Type;
