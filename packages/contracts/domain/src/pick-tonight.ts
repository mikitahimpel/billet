import { Schema } from "effect";
import { EpochMillis } from "./ids.ts";
import { ListItemId, ListItemText, MediaKind, TmdbId, TmdbImagePath } from "./list.ts";

/** ✕ not tonight, 👁 seen it, ♥ want to. */
export const PickChoice = Schema.Literals(["pass", "seen", "want"]);
export type PickChoice = typeof PickChoice.Type;

/** A card of the deck: an item on the pair's To watch list, or a TMDB title that is not on it. */
export const PickTitle = Schema.TaggedUnion({
  Item: { item: ListItemId },
  Title: { kind: MediaKind, tmdb: TmdbId },
});
export type PickTitle = typeof PickTitle.Type;

/**
 * A title both partners swiped ♥ within one session. `name` and `posterPath` are what the second
 * swipe sent; `at` is when it made the match.
 */
export const PickMatch = Schema.Struct({
  title: PickTitle,
  name: ListItemText,
  posterPath: Schema.optionalKey(TmdbImagePath),
  at: EpochMillis,
});
export type PickMatch = typeof PickMatch.Type;
