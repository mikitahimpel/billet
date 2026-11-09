import { Schema } from "effect";
import { Color } from "./ink.ts";

export const DatePlace = Schema.Literals(["home", "city", "nature", "apart"]);
export type DatePlace = typeof DatePlace.Type;

export const DateCost = Schema.Literals(["free", "$", "$$"]);
export type DateCost = typeof DateCost.Type;

export const DateLength = Schema.Literals(["1h", "evening", "day"]);
export type DateLength = typeof DateLength.Type;

export const DateSeason = Schema.Literals(["any", "spring", "summer", "autumn", "winter"]);
export type DateSeason = typeof DateSeason.Type;

/** The file name carries a content hash, so a path is cached for good. `color` is the average
 * colour, shown while it loads. */
export const DateArt = Schema.Struct({
  path: Schema.String.check(Schema.isPattern(/^\/art\/dates\/[a-z0-9-]+\.webp$/)),
  color: Color,
});
export type DateArt = typeof DateArt.Type;

/** `title` and `pitch` may hold `{cat}`, which the app replaces with the cat's name. */
export const DateIdea = Schema.Struct({
  id: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)),
  title: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(60)),
  pitch: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(120)),
  place: DatePlace,
  cost: DateCost,
  time: DateLength,
  season: DateSeason,
  art: DateArt,
});
export type DateIdea = typeof DateIdea.Type;
