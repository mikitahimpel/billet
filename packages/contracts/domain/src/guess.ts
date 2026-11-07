import { Schema } from "effect";
import { LocalDay } from "./coins.ts";
import { EpochMillis, UserId } from "./ids.ts";

/** A question of the Who knows who catalog, numbered once and never reused. */
export const GuessQuestionId = Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)).pipe(
  Schema.brand("GuessQuestionId"),
);
export type GuessQuestionId = typeof GuessQuestionId.Type;

/** Which of a question's four options, from 0. */
export const GuessOption = Schema.Int.check(Schema.isBetween({ minimum: 0, maximum: 3 }));
export type GuessOption = typeof GuessOption.Type;

export const GuessTag = Schema.Literals([
  "food",
  "habits",
  "past",
  "music",
  "money",
  "us",
  "dreams",
  "quirks",
]);
export type GuessTag = typeof GuessTag.Type;

const OptionText = Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(80));

/**
 * One question. `guess` is what the guesser reads, with `{name}` for the subject's name; `self` is
 * the same question as the subject reads it.
 */
export const GuessQuestion = Schema.Struct({
  id: GuessQuestionId,
  guess: Schema.String.check(Schema.isIncluding("{name}"), Schema.isMaxLength(160)),
  self: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(160)),
  options: Schema.Tuple([OptionText, OptionText, OptionText, OptionText]),
  tag: GuessTag,
});
export type GuessQuestion = typeof GuessQuestion.Type;

/**
 * The pair's round of one room day: `id` is that day. The subject answers about themselves and the
 * other member guesses. `closesAt` is when the day ends; a round not finished by then is never
 * scored.
 */
export const GuessRound = Schema.Struct({
  id: LocalDay,
  subject: UserId,
  questions: Schema.Array(GuessQuestionId),
  closesAt: EpochMillis,
});
export type GuessRound = typeof GuessRound.Type;

/** One locked answer: the subject's truth, or the guesser's guess. */
export const GuessAnswer = Schema.Struct({ question: GuessQuestionId, option: GuessOption });
export type GuessAnswer = typeof GuessAnswer.Type;

/** One question opened after both members answered the whole round. */
export const GuessReveal = Schema.Struct({
  question: GuessQuestionId,
  truth: GuessOption,
  guess: GuessOption,
  hit: Schema.Boolean,
});
export type GuessReveal = typeof GuessReveal.Type;

const Points = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** Points of the caller and of the partner. A point is a hit while guessing. */
export const GuessTally = Schema.Struct({ mine: Points, partner: Points });
export type GuessTally = typeof GuessTally.Type;

/**
 * The pair's score. `weekOf` is the Monday the current week started on, in room time; `bestWeek`
 * is each member's own highest week.
 */
export const GuessScore = Schema.Struct({
  weekOf: LocalDay,
  week: GuessTally,
  allTime: GuessTally,
  bestWeek: GuessTally,
});
export type GuessScore = typeof GuessScore.Type;
