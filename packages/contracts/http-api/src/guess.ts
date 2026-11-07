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
 * `GET /v1/guess`, and the answer to an answer: today's round as the caller sees it. `answers` are
 * the caller's own, in the order given; the partner's stay hidden, counted in `partnerAnswered`,
 * until both have answered every question. Then `reveal` holds each question in round order.
 */
export const GuessResponse = Schema.Struct({
  round: GuessRound,
  answers: Schema.Array(GuessAnswer),
  partnerAnswered: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
  reveal: Schema.optionalKey(Schema.Array(GuessReveal)),
  score: GuessScore,
});
export type GuessResponse = typeof GuessResponse.Type;

/**
 * `POST /v1/guess/answers`: one answer to a question of today's round. The subject's is the truth,
 * the guesser's a guess. It locks: the same option again changes nothing, another one is refused.
 */
export const GuessAnswerRequest = Schema.Struct({
  round: LocalDay,
  question: GuessQuestionId,
  option: GuessOption,
});
export type GuessAnswerRequest = typeof GuessAnswerRequest.Type;

/**
 * `GET /v1/guess/catalog`: every question. `version` changes with the questions and is the
 * response's ETag, so a client that has it gets a 304.
 */
export const GuessCatalogResponse = Schema.Struct({
  version: Schema.String.check(Schema.isPattern(/^[0-9a-f]{16}$/)),
  questions: Schema.Array(GuessQuestion),
});
export type GuessCatalogResponse = typeof GuessCatalogResponse.Type;
