import { makeInMemoryPlusRepository } from "./in-memory-plus-repository.ts";
import { plusRepositoryContract } from "./plus-repository-contract.ts";

plusRepositoryContract("in-memory", () => Promise.resolve(makeInMemoryPlusRepository()));
