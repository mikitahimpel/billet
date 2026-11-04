import { env } from "cloudflare:workers";
import { Effect, Layer, Scope } from "effect";
import { beforeEach } from "vitest";
import { OnboardingRepository } from "@billet/backend-onboarding/onboarding-repository";
import { describeOnboardingRepositoryContract } from "@billet/backend-onboarding/test/onboarding-repository-contract";
import { OnboardingRepositoryLive } from "../src/onboarding-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repositoryOn = (binding: D1Database) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(
        OnboardingRepositoryLive(binding),
        yield* Scope.make(),
      );
      return context.mapUnsafe.get(OnboardingRepository.key) as OnboardingRepository["Service"];
    }),
  );

beforeEach(resetDirectory);

// The contract's users must exist: an answer points at its account.
describeOnboardingRepositoryContract("D1", async () => {
  await env.DB.batch(
    ["u1", "u2"].map((id) =>
      env.DB.prepare("INSERT INTO users (id, created_at) VALUES (?, 1)").bind(id),
    ),
  );
  return repositoryOn(env.DB);
});
