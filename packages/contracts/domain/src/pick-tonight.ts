import { Schema } from "effect";
import { EpochMillis } from "./ids.ts";
import { ListItemId, ListItemText, MediaKind, TmdbId, TmdbImagePath } from "./list.ts";

/** ✕ not tonight, 👁 seen it, ♥ want to. */
export const PickChoice = Schema.Literals(["pass", "seen", "want"]);
export type PickChoice = typeof PickChoice.Type;

/** `Title` is a TMDB title not on the pair's To watch list. */
export const PickTitle = Schema.TaggedUnion({
  Item: { item: ListItemId },
  Title: { kind: MediaKind, tmdb: TmdbId },
});
export type PickTitle = typeof PickTitle.Type;

/** Both swiped ♥ within one session. `name`, `posterPath` and `at` come from the second swipe. */
export const PickMatch = Schema.Struct({
  title: PickTitle,
  name: ListItemText,
  posterPath: Schema.optionalKey(TmdbImagePath),
  at: EpochMillis,
});
export type PickMatch = typeof PickMatch.Type;
