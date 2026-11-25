import { env } from "cloudflare:workers";
import { Effect, Layer, Scope } from "effect";
import { beforeAll } from "vitest";
import { PlusRepository } from "@billet/backend-payments/plus-repository";
import { plusRepositoryContract } from "@billet/backend-payments/test/plus-repository-contract";
import { PlusRepositoryLive } from "../src/plus-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repositoryOn = (binding: D1Database) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(PlusRepositoryLive(binding), yield* Scope.make());
      return context.mapUnsafe.get(PlusRepository.key) as PlusRepository["Service"];
    }),
  );

beforeAll(async () => {
  await resetDirectory();
});

// Ids are fresh per test, so the tests share one database.
plusRepositoryContract("D1", () => repositoryOn(env.DB));
