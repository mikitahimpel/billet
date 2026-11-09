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

/** One answer per account and step. Contract: `test/onboarding-repository-contract.ts`. */
export class OnboardingRepository extends Context.Service<
  OnboardingRepository,
  {
    /** Keeps whichever answer to the step has the later `answeredAt`. Safe to call concurrently. */
    readonly save: (answer: StoredOnboardingAnswer) => Effect.Effect<void, OnboardingUnavailable>;
    /** The account's answers, in no set order. */
    readonly answersOf: (
      userId: UserId,
    ) => Effect.Effect<ReadonlyArray<StoredOnboardingAnswer>, OnboardingUnavailable>;
  }
>()("@billet/backend-onboarding/OnboardingRepository") {}
