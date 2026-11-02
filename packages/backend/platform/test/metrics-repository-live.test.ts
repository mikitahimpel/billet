import { env } from "cloudflare:workers";
import { Effect, Layer, Scope } from "effect";
import { beforeEach } from "vitest";
import { MetricsRepository } from "@billet/backend-metrics/metrics-repository";
import { describeMetricsRepositoryContract } from "@billet/backend-metrics/test/metrics-repository-contract";
import { MetricsRepositoryLive } from "../src/metrics-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repositoryOn = (binding: D1Database) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(
        MetricsRepositoryLive(binding),
        yield* Scope.make(),
      );
      return context.mapUnsafe.get(MetricsRepository.key) as MetricsRepository["Service"];
    }),
  );

beforeEach(resetDirectory);

describeMetricsRepositoryContract("D1", () => repositoryOn(env.DB));
