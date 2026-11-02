import { makeInMemoryPairingRepository } from "./in-memory-pairing-repository.ts";
import { describePairingRepositoryContract } from "./pairing-repository-contract.ts";

describePairingRepositoryContract("in-memory fake", () =>
  Promise.resolve(makeInMemoryPairingRepository().repository),
);
