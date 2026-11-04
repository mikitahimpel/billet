import { Schema } from "effect";
import { EpochMillis } from "@billet/contracts-domain/ids";
import {
  OnboardingAnswer,
  OnboardingStep,
  OnboardingStepId,
  OnboardingVersion,
} from "@billet/contracts-domain/onboarding";

/**
 * The onboarding questions, in order. They are server config, so they change without an app
 * release; the app ships a copy for when it is offline. Step and option ids never change meaning.
 */
export const OnboardingResponse = Schema.Struct({
  version: OnboardingVersion,
  steps: Schema.Array(OnboardingStep),
});
export type OnboardingResponse = typeof OnboardingResponse.Type;

/**
 * One step's answer, or its skip. The server keeps one answer per account and step: sending again
 * replaces it, unless the stored one has a later `answeredAt`, so a queued retry never undoes a
 * newer answer. `answeredAt` is the phone's clock; one in the future is stored as the server's now.
 * An answer to a step or option the current catalogue lacks is a 400, which the app drops.
 */
export const SaveOnboardingAnswerRequest = Schema.Struct({
  version: OnboardingVersion,
  stepId: OnboardingStepId,
  answer: OnboardingAnswer,
  answeredAt: EpochMillis,
});
export type SaveOnboardingAnswerRequest = typeof SaveOnboardingAnswerRequest.Type;
