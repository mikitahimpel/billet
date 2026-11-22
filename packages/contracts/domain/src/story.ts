import { Schema } from "effect";
import { EpochMillis } from "./ids.ts";

/** An episode, a beat or a suspect: lowercase words joined by hyphens, named by the app's content. */
export const StoryId = Schema.String.check(
  Schema.isPattern(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/),
  Schema.isMaxLength(40),
).pipe(Schema.brand("StoryId"));
export type StoryId = typeof StoryId.Type;

/** `found`: the member found a beat's clue. `named`: the member named a suspect. */
export const StoryMarkKind = Schema.Literals(["found", "named"]);
export type StoryMarkKind = typeof StoryMarkKind.Type;

/** `ref` is the beat id for `found` and the suspect id for `named`. No text, only ids and times. */
export const StoryMark = Schema.Struct({
  episode: StoryId,
  kind: StoryMarkKind,
  ref: StoryId,
  at: EpochMillis,
});
export type StoryMark = typeof StoryMark.Type;
