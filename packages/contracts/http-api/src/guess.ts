import { Schema } from "effect";
import { LocalDay } from "@billet/contracts-domain/coins";
import {
  GuessAnswer,
  GuessOption,
  GuessQuestion,
  GuessQuestionId,
  GuessReveal,
  GuessRound,
  GuessScore,
} from "@billet/contracts-domain/guess";

/**
 * `answers`: the caller's own. The partner's stay hidden until both answered all; then `reveal`.
 */
export const GuessResponse = Schema.Struct({
  round: GuessRound,
  answers: Schema.Array(GuessAnswer),
  partnerAnswered: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
  reveal: Schema.optionalKey(Schema.Array(GuessReveal)),
  score: GuessScore,
});
export type GuessResponse = typeof GuessResponse.Type;

/** The subject's is the truth, the guesser's a guess. Locks: a different option is refused. */
export const GuessAnswerRequest = Schema.Struct({
  round: LocalDay,
  question: GuessQuestionId,
  option: GuessOption,
});
export type GuessAnswerRequest = typeof GuessAnswerRequest.Type;

/** `GET /v1/guess/catalog`. `version` is the ETag, so a client that has it gets a 304. */
export const GuessCatalogResponse = Schema.Struct({
  version: Schema.String.check(Schema.isPattern(/^[0-9a-f]{16}$/)),
  questions: Schema.Array(GuessQuestion),
});
export type GuessCatalogResponse = typeof GuessCatalogResponse.Type;
