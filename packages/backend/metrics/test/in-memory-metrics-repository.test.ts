import { describeMetricsRepositoryContract } from "./metrics-repository-contract.ts";
import { makeInMemoryMetricsRepository } from "./in-memory-metrics-repository.ts";

describeMetricsRepositoryContract(
  "in-memory",
  async () => makeInMemoryMetricsRepository().repository,
);
