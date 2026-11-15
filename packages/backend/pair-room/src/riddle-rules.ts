import { Schema } from "effect";
import { EpochMillis, IdempotencyKey, MediaKey, UserId } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import {
  normaliseRiddleText,
  RevealedLetter,
  type Riddle,
  RiddleId,
  RiddleLetter,
  riddleMinDecoys,
  riddleShapeOf,
  RiddleState,
  riddleTileCount,
  RiddleWord,
} from "@billet/contracts-domain/riddle";
import type { SendRiddleRequest } from "@billet/contracts-http-api/riddle";
import { generator, hash, shuffled } from "./seeded.ts";

const Count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** One riddle as the room keeps it: the word always, whoever asks. */
export const RiddleRow = Schema.Struct({
  id: RiddleId,
  drawer: UserId,
  word: RiddleWord,
  compact: CompactStrokes,
  image: MediaKey,
  tiles: Schema.Array(RiddleLetter),
  removed: Schema.Array(Count),
  revealed: Schema.Array(RevealedLetter),
  hints: Count,
  tries: Count,
  state: RiddleState,
  at: EpochMillis,
});
export type RiddleRow = typeof RiddleRow.Type;

/** One try at a riddle under the guesser's `key`, and whether it was the word. */
export const RiddleGuessRow = Schema.Struct({
  riddle: RiddleId,
  key: IdempotencyKey,
  right: Schema.Boolean,
  at: EpochMillis,
});
export type RiddleGuessRow = typeof RiddleGuessRow.Type;

/** Solves in a row since the last give-up, and the longest run the pair had. */
export const RiddleSeries = Schema.Struct({ series: Count, best: Count });
export type RiddleSeries = typeof RiddleSeries.Type;

export const noRiddleSeries: RiddleSeries = { series: 0, best: 0 };

/** What one riddle command stores, all at once: the riddle, the try that changed it, the series. */
export const RiddleWrite = Schema.Struct({
  riddle: RiddleRow,
  guess: Schema.optionalKey(RiddleGuessRow),
  series: Schema.optionalKey(RiddleSeries),
});
export type RiddleWrite = typeof RiddleWrite.Type;

/** The `GamePlayed` a round that ended earns its guesser: `score` is its coins. */
export const RiddleReward = Schema.Struct({ won: Schema.Boolean, score: Count });
export type RiddleReward = typeof RiddleReward.Type;

/** A solve with no hint. */
export const solveCoins = 3;
/** What each hint takes off a solve. */
export const hintCost = 1;
/** The least a solve pays, however many hints it took. */
export const solveFloor = 1;
/** What a give-up pays: the pair played, and that counts. */
export const giveUpCoins = 1;

export const solveReward = (hints: number): RiddleReward => ({
  won: true,
  score: Math.max(solveFloor, solveCoins - hintCost * hints),
});

export const giveUpReward: RiddleReward = { won: false, score: giveUpCoins };

const alphabet = "abcdefghijklmnopqrstuvwxyz";
const decodeLetter = Schema.decodeSync(RiddleLetter);
const decodeWord = Schema.decodeOption(RiddleWord);

const lettersOf = (word: string): ReadonlyArray<RiddleLetter> =>
  [...word.replaceAll(" ", "")].map((letter) => decodeLetter(letter));

/** The word's letters plus decoys, 12 tiles with two decoys at least, shuffled; seed-stable. */
export const tilesFor = (word: RiddleWord, seed: string): ReadonlyArray<RiddleLetter> => {
  const letters = lettersOf(word);
  const next = generator(hash(`${seed}:decoys`));
  const decoys = Array.from(
    { length: Math.max(riddleMinDecoys, riddleTileCount - letters.length) },
    () => decodeLetter(alphabet[Math.floor(next() * alphabet.length)] ?? "a"),
  );
  return shuffled([...letters, ...decoys], hash(`${seed}:tiles`));
};

/** The indexes of the tiles the word does not need. Equal letters are interchangeable. */
export const decoysOf = (row: Pick<RiddleRow, "word" | "tiles">): ReadonlyArray<number> => {
  const needed = [...lettersOf(row.word)];
  return row.tiles.flatMap((tile, index) => {
    const at = needed.indexOf(tile);
    if (at < 0) return [index];
    needed.splice(at, 1);
    return [];
  });
};

/** What the guesser sees of `row`: the word only once the round has ended. The drawer sees all. */
export const riddleView = (row: RiddleRow, caller: UserId): Riddle => ({
  id: row.id,
  drawer: row.drawer,
  shape: riddleShapeOf(row.word),
  tiles: row.tiles,
  revealed: row.revealed,
  removed: row.removed,
  hints: row.hints,
  tries: row.tries,
  state: row.state,
  ...(caller === row.drawer || row.state._tag !== "Open" ? { word: row.word } : {}),
  compact: row.compact,
  image: row.image,
  at: row.at,
});

export const endedAt = (row: RiddleRow): EpochMillis | undefined =>
  row.state._tag === "Open" ? undefined : row.state.at;

export const RiddleRefusal = Schema.Literals([
  /** The caller is not a member of an open room. */
  "NotOpen",
  "NotFound",
  /** A word that is not a `RiddleWord` once trimmed and lowercased. */
  "BadWord",
  /** A send under an id the partner's riddle already has. */
  "IdTaken",
  /** The drawer has a riddle the partner has not finished yet. */
  "RiddleOpen",
  /** A try, a hint or a give-up by the riddle's own drawer. */
  "NotGuesser",
  "RiddleClosed",
  /** Every hint is used: the decoys halved and all letters but one shown. */
  "NoHint",
]);
export type RiddleRefusal = typeof RiddleRefusal.Type;

/**
 * Refused; a retry, answered as the first was; or a write, with the reward if the round ended.
 */
export type RiddleDecision =
  | { readonly _tag: "Refused"; readonly reason: RiddleRefusal }
  | { readonly _tag: "Repeated"; readonly riddle: RiddleRow; readonly right?: boolean }
  | {
      readonly _tag: "Stored";
      readonly write: RiddleWrite;
      readonly reward?: RiddleReward;
      readonly right?: boolean;
    };

const refused = (reason: RiddleRefusal): RiddleDecision => ({ _tag: "Refused", reason });

/**
 * `existing` is the riddle under the request's id; a member has one open riddle at a time.
 */
export const decideSend = (
  existing: RiddleRow | undefined,
  open: ReadonlyArray<RiddleRow>,
  by: UserId,
  request: SendRiddleRequest,
  at: EpochMillis,
): RiddleDecision => {
  if (existing !== undefined) {
    return existing.drawer === by ? { _tag: "Repeated", riddle: existing } : refused("IdTaken");
  }
  const word = decodeWord(normaliseRiddleText(request.word));
  if (word._tag === "None") return refused("BadWord");
  if (open.some((riddle) => riddle.drawer === by)) return refused("RiddleOpen");
  const riddle: RiddleRow = {
    id: request.id,
    drawer: by,
    word: word.value,
    compact: request.compact,
    image: request.image,
    tiles: tilesFor(word.value, request.id),
    removed: [],
    revealed: [],
    hints: 0,
    tries: 0,
    state: { _tag: "Open" },
    at,
  };
  return { _tag: "Stored", write: { riddle } };
};

/** Whether `by` may still play `row`: its guesser, while it is open. */
const playable = (row: RiddleRow, by: UserId): RiddleRefusal | undefined => {
  if (row.drawer === by) return "NotGuesser";
  if (row.state._tag !== "Open") return "RiddleClosed";
  return undefined;
};

/**
 * A retry under the same key answers with the stored try and counts nothing, even after the end.
 */
export const decideGuess = (
  row: RiddleRow,
  earlier: RiddleGuessRow | undefined,
  series: RiddleSeries,
  by: UserId,
  request: { readonly key: IdempotencyKey; readonly guess: string },
  at: EpochMillis,
): RiddleDecision => {
  if (row.drawer === by) return refused("NotGuesser");
  if (earlier !== undefined) return { _tag: "Repeated", riddle: row, right: earlier.right };
  const closed = playable(row, by);
  if (closed !== undefined) return refused(closed);
  const right = normaliseRiddleText(request.guess) === row.word;
  const guess: RiddleGuessRow = { riddle: row.id, key: request.key, right, at };
  const tried = { ...row, tries: row.tries + 1 };
  if (!right) return { _tag: "Stored", write: { riddle: tried, guess }, right };
  const next = series.series + 1;
  return {
    _tag: "Stored",
    write: {
      riddle: { ...tried, state: { _tag: "Solved", at } },
      guess,
      series: { series: next, best: Math.max(series.best, next) },
    },
    reward: solveReward(row.hints),
    right,
  };
};

/**
 * The first hint halves the decoys; each later one places a letter until one is left. Seeded.
 */
export const decideHint = (row: RiddleRow, by: UserId): RiddleDecision => {
  const closed = playable(row, by);
  if (closed !== undefined) return refused(closed);
  const hints = row.hints + 1;
  if (row.hints === 0) {
    const decoys = decoysOf(row);
    const removed = shuffled(decoys, hash(`${row.id}:removed`))
      .slice(0, Math.floor(decoys.length / 2))
      .toSorted((a, b) => a - b);
    return { _tag: "Stored", write: { riddle: { ...row, removed, hints } } };
  }
  const letters = lettersOf(row.word);
  if (row.revealed.length >= letters.length - 1) return refused("NoHint");
  const shown = new Set(row.revealed.map((letter) => letter.index));
  const hidden = letters.flatMap((_, index) => (shown.has(index) ? [] : [index]));
  const [index] = shuffled(hidden, hash(`${row.id}:hint:${hints}`));
  const letter = index === undefined ? undefined : letters[index];
  if (index === undefined || letter === undefined) return refused("NoHint");
  return {
    _tag: "Stored",
    write: { riddle: { ...row, revealed: [...row.revealed, { index, letter }], hints } },
  };
};

/** `by` gives up: the word shows, the round pays a little, and the series starts again. */
export const decideGiveUp = (
  row: RiddleRow,
  series: RiddleSeries,
  by: UserId,
  at: EpochMillis,
): RiddleDecision => {
  const closed = playable(row, by);
  if (closed !== undefined) return refused(closed);
  return {
    _tag: "Stored",
    write: {
      riddle: { ...row, state: { _tag: "GivenUp", at } },
      series: { series: 0, best: series.best },
    },
    reward: giveUpReward,
  };
};
