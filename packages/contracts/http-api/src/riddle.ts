import { Schema } from "effect";
import { IdempotencyKey, MediaKey } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { Riddle, RiddleId } from "@billet/contracts-domain/riddle";

const Count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** Typed text, before the room trims and lowercases it. */
const TypedText = Schema.String.check(Schema.isMaxLength(64));

/**
 * `GET /v1/riddles`: the pair's draw-guess as the caller sees it. `open` holds at most one riddle
 * per member; `ended` the last 20 that ended, newest first. `series` counts solves in a row since
 * the last give-up, and `best` is the longest it has been.
 */
export const RiddlesResponse = Schema.Struct({
  open: Schema.Array(Riddle),
  ended: Schema.Array(Riddle),
  series: Count,
  best: Count,
});
export type RiddlesResponse = typeof RiddlesResponse.Type;

/**
 * `POST /v1/riddles`: a drawing for the partner to guess, answered with the riddle. `id` is the
 * drawer's own and makes a retry answer with the first send. `word` is trimmed and lowercased,
 * then must be a `RiddleWord`. `image` is the PNG uploaded through `uploadImage` first.
 */
export const SendRiddleRequest = Schema.Struct({
  id: RiddleId,
  word: TypedText,
  compact: CompactStrokes,
  image: MediaKey,
});
export type SendRiddleRequest = typeof SendRiddleRequest.Type;

/**
 * `POST /v1/riddles/:id/guess`: one try. `key` is the guesser's own for this try: a retry with it
 * answers with the first try's result and counts nothing more.
 */
export const GuessRiddleRequest = Schema.Struct({ key: IdempotencyKey, guess: TypedText });
export type GuessRiddleRequest = typeof GuessRiddleRequest.Type;

/** The riddle after a try, and whether that try was the word. */
export const GuessRiddleResponse = Schema.Struct({ riddle: Riddle, right: Schema.Boolean });
export type GuessRiddleResponse = typeof GuessRiddleResponse.Type;
