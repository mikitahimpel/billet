import { env } from "cloudflare:workers";
import { Effect, Layer, Scope } from "effect";
import { beforeEach } from "vitest";
import { FlagsRepository } from "@billet/backend-flags/flags-repository";
import { describeFlagsRepositoryContract } from "@billet/backend-flags/test/flags-repository-contract";
import { FlagsRepositoryLive } from "../src/flags-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repositoryOn = (binding: D1Database) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(
        FlagsRepositoryLive(binding),
        yield* Scope.make(),
      );
      return context.mapUnsafe.get(FlagsRepository.key) as FlagsRepository["Service"];
    }),
  );

beforeEach(resetDirectory);

describeFlagsRepositoryContract("D1", () => repositoryOn(env.DB));
