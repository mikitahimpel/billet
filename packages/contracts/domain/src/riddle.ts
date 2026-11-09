import { Schema } from "effect";
import { EpochMillis, IdempotencyKey, MediaKey, UserId } from "./ids.ts";
import { CompactStrokes } from "./ink.ts";

/** Spaces counted. */
export const riddleWordMaxLength = 24;

/** Spaces not counted. */
export const riddleWordMaxLetters = 12;

/** Unless a long word needs more for its two decoys. */
export const riddleTileCount = 12;

export const riddleMinDecoys = 2;

/** Repeated on every retry of the same send. */
export const RiddleId = IdempotencyKey.pipe(Schema.brand("RiddleId"));
export type RiddleId = typeof RiddleId.Type;

export const RiddleLetter = Schema.String.check(Schema.isPattern(/^[a-z]$/));
export type RiddleLetter = typeof RiddleLetter.Type;

export const RiddleWord = Schema.String.check(
  Schema.makeFilter(
    (word) =>
      (/^[a-z]+( [a-z]+)*$/.test(word) &&
        word.length <= riddleWordMaxLength &&
        word.replaceAll(" ", "").length <= riddleWordMaxLetters) ||
      `expected lowercase words of a to z, single-spaced, at most ${riddleWordMaxLength} characters and ${riddleWordMaxLetters} letters`,
  ),
).pipe(Schema.brand("RiddleWord"));
export type RiddleWord = typeof RiddleWord.Type;

export const normaliseRiddleText = (text: string): string => text.trim().toLowerCase();

/** "north pole" is [5, 4]. */
export const riddleShapeOf = (word: string): ReadonlyArray<number> =>
  word.split(" ").map((part) => part.length);

const Count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** `index` counts the word's letters from 0, spaces not counted. */
export const RevealedLetter = Schema.Struct({ index: Count, letter: RiddleLetter });
export type RevealedLetter = typeof RevealedLetter.Type;

export const RiddleState = Schema.TaggedUnion({
  Open: {},
  Solved: { at: EpochMillis },
  GivenUp: { at: EpochMillis },
});
export type RiddleState = typeof RiddleState.Type;

/** As a member sees it: the guesser never gets `word` while it is open. `removed`: indexes of the
 * tiles the first hint took away. */
export const Riddle = Schema.Struct({
  id: RiddleId,
  drawer: UserId,
  shape: Schema.Array(Schema.Int.check(Schema.isGreaterThanOrEqualTo(1))),
  tiles: Schema.Array(RiddleLetter),
  revealed: Schema.Array(RevealedLetter),
  removed: Schema.Array(Count),
  hints: Count,
  tries: Count,
  state: RiddleState,
  word: Schema.optionalKey(RiddleWord),
  compact: CompactStrokes,
  image: MediaKey,
  at: EpochMillis,
});
export type Riddle = typeof Riddle.Type;
