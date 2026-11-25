import type { StoredOnboardingAnswer } from "./onboarding-repository.ts";

/** The onboarding step and the option that mean the account said it is 13 to 17. */
export const ageStepId = "age";
export const minorOptionId = "age-13-17";

/**
 * Whether the account answered 13 to 17. A skip, no answer, or an older answer replaced by a
 * newer one is not a declaration. Only the latest answer to the step counts, which is the one
 * the repository keeps.
 */
export const declaresMinor = (answers: ReadonlyArray<StoredOnboardingAnswer>): boolean =>
  answers.some(
    ({ stepId, answer }) =>
      stepId === ageStepId && answer._tag === "Single" && answer.option === minorOptionId,
  );
