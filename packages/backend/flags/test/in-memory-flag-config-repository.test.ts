import { describeFlagConfigRepositoryContract } from "./flag-config-repository-contract.ts";
import { makeInMemoryFlagConfigRepository } from "./in-memory-flag-config-repository.ts";

describeFlagConfigRepositoryContract(
  "in-memory",
  async () => makeInMemoryFlagConfigRepository().repository,
);
