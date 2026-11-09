import { Schema } from "effect";
import { EpochMillis } from "@billet/contracts-domain/ids";
import {
  OnboardingAnswer,
  OnboardingStep,
  OnboardingStepId,
  OnboardingVersion,
} from "@billet/contracts-domain/onboarding";

/** Server config, so it changes without a release. Step and option ids never change meaning. */
export const OnboardingResponse = Schema.Struct({
  version: OnboardingVersion,
  steps: Schema.Array(OnboardingStep),
});
export type OnboardingResponse = typeof OnboardingResponse.Type;

/**
 * One per account and step; an older `answeredAt` never replaces a newer one. Unknown ids: 400.
 */
export const SaveOnboardingAnswerRequest = Schema.Struct({
  version: OnboardingVersion,
  stepId: OnboardingStepId,
  answer: OnboardingAnswer,
  answeredAt: EpochMillis,
});
export type SaveOnboardingAnswerRequest = typeof SaveOnboardingAnswerRequest.Type;
