import { Effect, Layer } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { DemoBots } from "@billet/backend-demo-partner/demo-bots";
import { PairMoods } from "@billet/backend-pairing/pair-moods";
import { PairingObserver } from "@billet/backend-pairing/pairing-observer";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { PairingService } from "@billet/backend-pairing/pairing-service";
import { makeInMemoryPairingRepository } from "@billet/backend-pairing/test/in-memory-pairing-repository";
import { ReviewRepository } from "@billet/backend-review/review-repository";
import { ReviewService } from "@billet/backend-review/review-service";
import { makeInMemoryReviewRepository } from "@billet/backend-review/test/in-memory-review-repository";
import { reviewAdminApi, ReviewAdminRoutes } from "../src/admin-review.ts";
import { CurrentAdmin } from "../src/admin-routes.ts";

const base = Layer.mergeAll(Digest.layerWebCrypto, SecureRandom.layerWebCrypto);
const pairing = PairingService.layer.pipe(
  Layer.provide(
    Layer.mergeAll(
      Layer.succeed(PairingRepository, makeInMemoryPairingRepository().repository),
      PairingObserver.silent,
      PairMoods.none,
      base,
    ),
  ),
);
const review = ReviewService.layer.pipe(
  Layer.provide(
    Layer.mergeAll(
      pairing,
      Layer.succeed(DemoBots, { start: () => Effect.void, stop: () => Effect.void }),
      Layer.succeed(ReviewRepository, makeInMemoryReviewRepository().repository),
      base,
    ),
  ),
);
const panel = HttpRouter.toWebHandler(
  ReviewAdminRoutes.pipe(
    Layer.provide(
      Layer.mergeAll(review, Layer.succeed(CurrentAdmin, { email: "owner@example.com" })),
    ),
  ),
  { disableLogger: true },
);
afterAll(() => panel.dispose());

const call = async (path: string, method = "GET", body?: unknown) => {
  const response = await panel.handler(
    new Request(`https://api.billet.test${path}`, {
      method,
      ...(body === undefined
        ? {}
        : { body: JSON.stringify(body), headers: { "content-type": "application/json" } }),
    }),
  );
  const text = await response.text();
  return { status: response.status, body: text === "" ? undefined : JSON.parse(text) };
};

describe("the review pair's admin", () => {
  it("issues a code shown once, lists it by its last four, revokes and wipes", async () => {
    const issued = await call(reviewAdminApi.code, "POST", { days: 7 });
    expect(issued.status).toBe(201);
    const code = issued.body.code as string;
    expect(code).toMatch(/^[2-9A-HJ-NP-Z]{26}$/);

    const status = await call(reviewAdminApi.review);
    expect(status.status).toBe(200);
    expect(JSON.stringify(status.body)).not.toContain(code);
    expect(status.body.codes).toMatchObject([
      { lastFour: code.slice(-4), live: true, createdBy: "owner@example.com" },
    ]);

    expect((await call(reviewAdminApi.revoke, "POST")).status).toBe(204);
    expect((await call(reviewAdminApi.wipe, "POST")).status).toBe(204);
    const after = await call(reviewAdminApi.review);
    expect(after.body.codes[0].live).toBe(false);
    expect(after.body.changes.map(({ action }: { action: string }) => action)).toEqual([
      "wipe",
      "revoke",
      "issue",
    ]);
  });

  it.each([[{ days: 0 }], [{ days: 31 }], [{}]])("refuses %j with 400", async (body) => {
    expect((await call(reviewAdminApi.code, "POST", body)).status).toBe(400);
  });
});
