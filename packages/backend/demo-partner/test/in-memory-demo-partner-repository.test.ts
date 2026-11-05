import { describeDemoPartnerRepositoryContract } from "./demo-partner-repository-contract.ts";
import { makeInMemoryDemoPartnerRepository } from "./in-memory-demo-partner-repository.ts";

describeDemoPartnerRepositoryContract("in-memory fake", () =>
  Promise.resolve(makeInMemoryDemoPartnerRepository().repository),
);
