import { describeOnboardingRepositoryContract } from "./onboarding-repository-contract.ts";
import { makeInMemoryOnboardingRepository } from "./in-memory-onboarding-repository.ts";

describeOnboardingRepositoryContract(
  "in-memory",
  async () => makeInMemoryOnboardingRepository().repository,
);
