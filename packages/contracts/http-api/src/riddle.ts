import { Schema } from "effect";
import { IdempotencyKey, MediaKey } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { Riddle, RiddleId } from "@billet/contracts-domain/riddle";

const Count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** Typed text, before the room trims and lowercases it. */
const TypedText = Schema.String.check(Schema.isMaxLength(64));

/**
 * `open`: at most one per member. `ended`: last 20, newest first. `series`: solves since a give-up.
 */
export const RiddlesResponse = Schema.Struct({
  open: Schema.Array(Riddle),
  ended: Schema.Array(Riddle),
  series: Count,
  best: Count,
});
export type RiddlesResponse = typeof RiddlesResponse.Type;

/**
 * A retried `id` gets the first send. `word` is trimmed, lowercased, then a `RiddleWord`.
 */
export const SendRiddleRequest = Schema.Struct({
  id: RiddleId,
  word: TypedText,
  compact: CompactStrokes,
  image: MediaKey,
});
export type SendRiddleRequest = typeof SendRiddleRequest.Type;

/** `POST /v1/riddles/:id/guess`: a retried `key` answers the first try and counts nothing more. */
export const GuessRiddleRequest = Schema.Struct({ key: IdempotencyKey, guess: TypedText });
export type GuessRiddleRequest = typeof GuessRiddleRequest.Type;

/** The riddle after a try, and whether that try was the word. */
export const GuessRiddleResponse = Schema.Struct({ riddle: Riddle, right: Schema.Boolean });
export type GuessRiddleResponse = typeof GuessRiddleResponse.Type;
