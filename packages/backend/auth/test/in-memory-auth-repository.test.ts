import { describeAuthRepositoryContract } from "./auth-repository-contract.ts";
import { makeInMemoryAuthRepository } from "./in-memory-auth-repository.ts";

describeAuthRepositoryContract("in-memory fake", () =>
  Promise.resolve(makeInMemoryAuthRepository().repository),
);
