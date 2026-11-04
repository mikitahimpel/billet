import { Effect } from "effect";
import type { OnboardingRepository, StoredOnboardingAnswer } from "../src/onboarding-repository.ts";

/** The test double for `OnboardingRepository`. Single-threaded, so each method is atomic. */
export const makeInMemoryOnboardingRepository = () => {
  const rows = new Map<string, StoredOnboardingAnswer>();
  const keyOf = (row: StoredOnboardingAnswer) => `${row.userId}/${row.stepId}`;

  const repository: OnboardingRepository["Service"] = {
    save: (answer) =>
      Effect.sync(() => {
        const earlier = rows.get(keyOf(answer));
        if (earlier === undefined || earlier.answeredAt <= answer.answeredAt) {
          rows.set(keyOf(answer), answer);
        }
      }),
    answersOf: (userId) =>
      Effect.sync(() => [...rows.values()].filter((row) => row.userId === userId)),
  };
  return { repository, rows };
};
