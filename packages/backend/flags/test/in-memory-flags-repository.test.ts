import { describeFlagsRepositoryContract } from "./flags-repository-contract.ts";
import { makeInMemoryFlagsRepository } from "./in-memory-flags-repository.ts";

describeFlagsRepositoryContract("in-memory", async () => makeInMemoryFlagsRepository().repository);
