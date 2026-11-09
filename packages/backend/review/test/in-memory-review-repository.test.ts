import { makeInMemoryReviewRepository } from "./in-memory-review-repository.ts";
import { describeReviewRepositoryContract } from "./review-repository-contract.ts";

describeReviewRepositoryContract(
  "in memory",
  async () => makeInMemoryReviewRepository().repository,
);
