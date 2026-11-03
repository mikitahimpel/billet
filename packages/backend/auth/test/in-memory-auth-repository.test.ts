import { describeAuthRepositoryContract } from "./auth-repository-contract.ts";
import { makeInMemoryAuthRepository } from "./in-memory-auth-repository.ts";

describeAuthRepositoryContract("in-memory", async () => ({
  repository: makeInMemoryAuthRepository().repository,
  seedDevice: async () => {},
}));
