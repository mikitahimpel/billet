import { Schema } from "effect";
import { StoryId, StoryMark, StoryMarkKind } from "@billet/contracts-domain/story";

/**
 * Every mark of the caller and of the partner. The partner's `named` marks of an episode stay out
 * until the caller has named a suspect in that episode.
 */
export const StoryResponse = Schema.Struct({
  mine: Schema.Array(StoryMark),
  partner: Schema.Array(StoryMark),
});
export type StoryResponse = typeof StoryResponse.Type;

/** `POST /v1/story/marks`: the same mark again changes nothing; a second `named` never replaces the first. */
export const StoryMarkRequest = Schema.Struct({
  episode: StoryId,
  kind: StoryMarkKind,
  ref: StoryId,
});
export type StoryMarkRequest = typeof StoryMarkRequest.Type;
