import { Schema } from "effect";
import { EpochMillis, IdempotencyKey, MediaKey, UserId } from "./ids.ts";
import { CompactStrokes } from "./ink.ts";

/** The most characters a riddle's word has, spaces counted. */
export const riddleWordMaxLength = 24;

/** The most letters a riddle's word has, spaces not counted. */
export const riddleWordMaxLetters = 12;

/** Tiles a guesser builds the word from, unless a long word needs more for its two decoys. */
export const riddleTileCount = 12;

/** The fewest decoys among the tiles. */
export const riddleMinDecoys = 2;

/** A riddle, named by its drawer once and repeated on every retry of the same send. */
export const RiddleId = IdempotencyKey.pipe(Schema.brand("RiddleId"));
export type RiddleId = typeof RiddleId.Type;

/** One tile: a lowercase letter a to z. */
export const RiddleLetter = Schema.String.check(Schema.isPattern(/^[a-z]$/));
export type RiddleLetter = typeof RiddleLetter.Type;

/**
 * A word to draw, as the room keeps it: lowercase a to z, single spaces between words, 1 to 24
 * characters and at most 12 letters.
 */
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

/** How a typed word or guess is compared: trimmed and lowercased. */
export const normaliseRiddleText = (text: string): string => text.trim().toLowerCase();

/** The letters of each word of `word`, so "north pole" is [5, 4]. */
export const riddleShapeOf = (word: string): ReadonlyArray<number> =>
  word.split(" ").map((part) => part.length);

const Count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** A letter Mochi's hint opened: `index` counts the word's letters from 0, spaces not counted. */
export const RevealedLetter = Schema.Struct({ index: Count, letter: RiddleLetter });
export type RevealedLetter = typeof RevealedLetter.Type;

export const RiddleState = Schema.TaggedUnion({
  Open: {},
  Solved: { at: EpochMillis },
  GivenUp: { at: EpochMillis },
});
export type RiddleState = typeof RiddleState.Type;

/**
 * One riddle as a member sees it. `tiles` are shuffled; `removed` are the indexes of the tiles the
 * first hint took away; `hints` and `tries` count what the guesser used. `word` is there for the
 * drawer, and for both once the round has ended: the guesser never gets it while it is open.
 */
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
