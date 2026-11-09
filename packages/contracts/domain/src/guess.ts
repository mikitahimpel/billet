import { Schema } from "effect";
import { LocalDay } from "./coins.ts";
import { EpochMillis, UserId } from "./ids.ts";

/** Never reused. */
export const GuessQuestionId = Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)).pipe(
  Schema.brand("GuessQuestionId"),
);
export type GuessQuestionId = typeof GuessQuestionId.Type;

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

/** `guess` is what the guesser reads, `{name}` being the subject; `self` is what the subject
 * reads. */
export const GuessQuestion = Schema.Struct({
  id: GuessQuestionId,
  guess: Schema.String.check(Schema.isIncluding("{name}"), Schema.isMaxLength(160)),
  self: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(160)),
  options: Schema.Tuple([OptionText, OptionText, OptionText, OptionText]),
  tag: GuessTag,
});
export type GuessQuestion = typeof GuessQuestion.Type;

/** `id` is the room day. The subject answers about themselves and the other member guesses. A
 * round not finished by `closesAt` is never scored. */
export const GuessRound = Schema.Struct({
  id: LocalDay,
  subject: UserId,
  questions: Schema.Array(GuessQuestionId),
  closesAt: EpochMillis,
});
export type GuessRound = typeof GuessRound.Type;

export const GuessAnswer = Schema.Struct({ question: GuessQuestionId, option: GuessOption });
export type GuessAnswer = typeof GuessAnswer.Type;

/** Opened after both members answered the whole round. */
export const GuessReveal = Schema.Struct({
  question: GuessQuestionId,
  truth: GuessOption,
  guess: GuessOption,
  hit: Schema.Boolean,
});
export type GuessReveal = typeof GuessReveal.Type;

const Points = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** A point is a hit while guessing. */
export const GuessTally = Schema.Struct({ mine: Points, partner: Points });
export type GuessTally = typeof GuessTally.Type;

/** `weekOf`: the current week's Monday, in room time. `bestWeek`: each member's own highest. */
export const GuessScore = Schema.Struct({
  weekOf: LocalDay,
  week: GuessTally,
  allTime: GuessTally,
  bestWeek: GuessTally,
});
export type GuessScore = typeof GuessScore.Type;
