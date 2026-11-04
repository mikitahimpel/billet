import { makeInMemoryPaymentsRepository } from "./in-memory-payments-repository.ts";
import { paymentsRepositoryContract } from "./payments-repository-contract.ts";

paymentsRepositoryContract("in-memory", () => Promise.resolve(makeInMemoryPaymentsRepository()));
