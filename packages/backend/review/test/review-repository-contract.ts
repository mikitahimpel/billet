import { Effect, Option, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import type { NewReviewCode, ReviewRepository } from "../src/review-repository.ts";

const user = Schema.decodeSync(UserId);
const partner = user("review-partner");

const code = (hash: string, createdAt: number, expiresAt = createdAt + 1_000): NewReviewCode => ({
  codeHash: hash,
  partnerId: partner,
  lastFour: hash.slice(-4).toUpperCase(),
  createdAt,
  createdBy: "owner@example.com",
  expiresAt,
});

/** The behaviour every `ReviewRepository` must have. `make` must return an empty repository. */
export const describeReviewRepositoryContract = (
  name: string,
  make: () => Promise<ReviewRepository["Service"]>,
): void => {
  describe(`ReviewRepository contract: ${name}`, () => {
    it("opens one partner, and knows it from anyone else", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          const before = yield* repository.partner;
          yield* repository.createPartner({ userId: partner, createdAt: 1 });
          return [
            before,
            yield* repository.partner,
            yield* repository.isPartner(partner),
            yield* repository.isPartner(user("someone")),
          ];
        }),
      );
      expect(found).toEqual([Option.none(), Option.some(partner), true, false]);
    });

    it("finds a code while it lives, and not after it expires", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.createPartner({ userId: partner, createdAt: 1 });
          yield* repository.issue(code("hash-aaaa", 100, 200));
          return [
            yield* repository.liveCode("hash-aaaa", 199),
            yield* repository.liveCode("hash-aaaa", 200),
            yield* repository.liveCode("hash-bbbb", 150),
          ];
        }),
      );
      expect(found).toEqual([Option.some(partner), Option.none(), Option.none()]);
    });

    it("revokes the earlier code when it issues a new one, and every code on revoke", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.createPartner({ userId: partner, createdAt: 1 });
          yield* repository.issue(code("hash-aaaa", 100));
          yield* repository.issue(code("hash-bbbb", 110));
          const afterIssue = [
            yield* repository.liveCode("hash-aaaa", 120),
            yield* repository.liveCode("hash-bbbb", 120),
          ];
          yield* repository.revoke({ at: 130, by: "owner@example.com" });
          return [...afterIssue, yield* repository.liveCode("hash-bbbb", 140)];
        }),
      );
      expect(found).toEqual([Option.none(), Option.some(partner), Option.none()]);
    });

    it("counts claims, lists codes and changes newest first", async () => {
      const repository = await make();
      const [codes, changes] = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.createPartner({ userId: partner, createdAt: 1 });
          yield* repository.issue(code("hash-aaaa", 100));
          yield* repository.issue(code("hash-bbbb", 110));
          yield* repository.claimed("hash-bbbb", 120);
          yield* repository.claimed("hash-bbbb", 125);
          yield* repository.record({ at: 130, by: "owner@example.com", action: "wipe" });
          return [yield* repository.codes(10), yield* repository.changes(10)] as const;
        }),
      );
      expect(
        codes.map(({ lastFour, claims, lastClaimedAt, revokedAt }) => ({
          lastFour,
          claims,
          lastClaimedAt,
          revokedAt,
        })),
      ).toEqual([
        { lastFour: "BBBB", claims: 2, lastClaimedAt: 125, revokedAt: null },
        { lastFour: "AAAA", claims: 0, lastClaimedAt: null, revokedAt: 110 },
      ]);
      expect(changes.map(({ action, lastFour, by }) => ({ action, lastFour, by }))).toEqual([
        { action: "wipe", lastFour: null, by: "owner@example.com" },
        { action: "issue", lastFour: "BBBB", by: "owner@example.com" },
        { action: "issue", lastFour: "AAAA", by: "owner@example.com" },
      ]);
    });
  });
};
