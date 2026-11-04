import { Context, type Effect, Schema } from "effect";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import {
  OnboardingAnswer,
  OnboardingStepId,
  OnboardingVersion,
} from "@billet/contracts-domain/onboarding";
import type { OnboardingUnavailable } from "./onboarding-error.ts";

/** One account's answer to one step, skips included. */
export const StoredOnboardingAnswer = Schema.Struct({
  userId: UserId,
  stepId: OnboardingStepId,
  version: OnboardingVersion,
  answer: OnboardingAnswer,
  answeredAt: EpochMillis,
});
export type StoredOnboardingAnswer = typeof StoredOnboardingAnswer.Type;

/**
 * Persistence for onboarding answers: one per account and step. The rows go with the account.
 * `test/onboarding-repository-contract.ts` is the behaviour any implementation must pass.
 */
export class OnboardingRepository extends Context.Service<
  OnboardingRepository,
  {
    /**
     * Stores the answer, replacing the account's earlier one to the same step unless that one has
     * a later `answeredAt`. A repeat of the same answer changes nothing. Safe to call at once.
     */
    readonly save: (answer: StoredOnboardingAnswer) => Effect.Effect<void, OnboardingUnavailable>;
    /** The account's answers, in no set order. */
    readonly answersOf: (
      userId: UserId,
    ) => Effect.Effect<ReadonlyArray<StoredOnboardingAnswer>, OnboardingUnavailable>;
  }
>()("@billet/backend-onboarding/OnboardingRepository") {}
