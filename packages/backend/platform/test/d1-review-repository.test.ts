import { env } from "cloudflare:workers";
import { Effect, Layer, Schema, Scope } from "effect";
import { beforeEach, describe, expect, it } from "vitest";
import { ReviewRepository } from "@billet/backend-review/review-repository";
import { describeReviewRepositoryContract } from "@billet/backend-review/test/review-repository-contract";
import { UserId } from "@billet/contracts-domain/ids";
import { ReviewRepositoryLive } from "../src/review-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repositoryOn = (binding: D1Database) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(
        ReviewRepositoryLive(binding),
        yield* Scope.make(),
      );
      return context.mapUnsafe.get(ReviewRepository.key) as ReviewRepository["Service"];
    }),
  );

describeReviewRepositoryContract("D1", async () => {
  await resetDirectory();
  return repositoryOn(env.DB);
});

describe("ReviewRepositoryLive on D1", () => {
  beforeEach(resetDirectory);

  it("opens the partner as a user, and drops it and its codes with that user", async () => {
    const repository = await repositoryOn(env.DB);
    const partner = Schema.decodeSync(UserId)("review-partner");
    await Effect.runPromise(
      Effect.gen(function* () {
        yield* repository.createPartner({ userId: partner, createdAt: 1 });
        yield* repository.issue({
          codeHash: "hash",
          partnerId: partner,
          lastFour: "WXYZ",
          createdAt: 2,
          createdBy: "owner@example.com",
          expiresAt: 3,
        });
      }),
    );
    expect(await env.DB.prepare("SELECT id FROM users").all()).toMatchObject({
      results: [{ id: "review-partner" }],
    });
    await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(partner).run();
    const left = await env.DB.batch([
      env.DB.prepare("SELECT * FROM review_partners"),
      env.DB.prepare("SELECT * FROM review_codes"),
    ]);
    expect(left.map(({ results }) => results)).toEqual([[], []]);
  });
});
