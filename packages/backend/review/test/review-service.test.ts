import { Duration, Effect, Layer, Option, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { DemoBots } from "@billet/backend-demo-partner/demo-bots";
import { PairMoods } from "@billet/backend-pairing/pair-moods";
import { PairingObserver } from "@billet/backend-pairing/pairing-observer";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { PairingService } from "@billet/backend-pairing/pairing-service";
import { makeInMemoryPairingRepository } from "@billet/backend-pairing/test/in-memory-pairing-repository";
import { ReviewCode, UserId } from "@billet/contracts-domain/ids";
import { ReviewRepository } from "../src/review-repository.ts";
import { ReviewService, reviewWelcomeNotes } from "../src/review-service.ts";
import { makeInMemoryReviewRepository } from "./in-memory-review-repository.ts";

const user = Schema.decodeSync(UserId);
const reviewer = user("reviewer-1");
const second = user("reviewer-2");
const someone = user("someone");
const admin = "owner@example.com";

const setup = () => {
  const pairs = makeInMemoryPairingRepository().repository;
  const review = makeInMemoryReviewRepository();
  const bots: Array<string> = [];
  const unpaired: Array<string> = [];
  const observer = Layer.succeed(PairingObserver, {
    invited: () => Effect.void,
    paired: () => Effect.void,
    unpaired: (pairId) => Effect.sync(() => unpaired.push(pairId)),
  });
  const pairing = PairingService.layer.pipe(
    Layer.provide(
      Layer.mergeAll(
        Layer.succeed(PairingRepository, pairs),
        observer,
        PairMoods.none,
        Digest.layerWebCrypto,
        SecureRandom.layerWebCrypto,
      ),
    ),
  );
  const demoBots = Layer.succeed(DemoBots, {
    start: (pairId, owner, bot, welcome) =>
      Effect.sync(() => bots.push(`start ${pairId} ${owner} ${bot} ${welcome?.length ?? 0}`)),
    stop: (pairId) => Effect.sync(() => bots.push(`stop ${pairId}`)),
  });
  const layer = Layer.mergeAll(
    ReviewService.layer.pipe(
      Layer.provide(
        Layer.mergeAll(
          pairing,
          demoBots,
          Layer.succeed(ReviewRepository, review.repository),
          Digest.layerWebCrypto,
          SecureRandom.layerWebCrypto,
        ),
      ),
    ),
    pairing,
  );
  const run = <A, E>(
    use: (
      service: ReviewService["Service"],
      pairing: PairingService["Service"],
    ) => Effect.Effect<A, E>,
  ) =>
    Effect.runPromise(
      Effect.gen(function* () {
        return yield* use(yield* ReviewService, yield* PairingService);
      }).pipe(Effect.provide(layer)),
    );
  const tagOf = <A, E extends { readonly _tag: string }>(
    use: (service: ReviewService["Service"]) => Effect.Effect<A, E>,
  ) =>
    run((service) =>
      use(service).pipe(
        Effect.flip,
        Effect.map(({ _tag }) => _tag),
      ),
    );
  return { review, bots, unpaired, run, tagOf };
};

describe("ReviewService", () => {
  it("issues a 26-symbol code that pairs the claimer with the review partner", async () => {
    const { review, bots, run } = setup();
    const issued = await run((service) => service.issue(admin, 7));
    expect(Schema.is(ReviewCode)(issued.code)).toBe(true);
    expect(issued.lastFour).toBe(issued.code.slice(-4));
    const [partner] = [...review.users];
    const pairId = await run((service) => service.claim(reviewer, issued.code));
    const pair = await run((_, pairing) => pairing.pair(reviewer));
    expect(pair).toMatchObject({ pairId, members: [reviewer, partner] });
    expect(bots).toEqual([`start ${pairId} ${reviewer} ${partner} ${reviewWelcomeNotes.length}`]);
    expect(JSON.stringify(review.codes)).not.toContain(issued.code);
  });

  it("resets the pair on each claim: a second claimer replaces the first", async () => {
    const { bots, unpaired, run } = setup();
    const { code } = await run((service) => service.issue(admin, 7));
    const first = await run((service) => service.claim(reviewer, code));
    const next = await run((service) => service.claim(second, code));
    expect(next).not.toBe(first);
    expect(unpaired).toEqual([first]);
    expect(bots).toContain(`stop ${first}`);
    expect(await run((_, pairing) => pairing.pair(reviewer).pipe(Effect.option))).toEqual(
      Option.none(),
    );
  });

  it("answers a reinstall that claims again with the pair it is already in", async () => {
    const { unpaired, run } = setup();
    const { code } = await run((service) => service.issue(admin, 7));
    const first = await run((service) => service.claim(reviewer, code));
    expect(await run((service) => service.claim(reviewer, code))).toBe(first);
    expect(unpaired).toEqual([]);
  });

  it("refuses a caller who has a partner of their own, and leaves both pairs alone", async () => {
    const { tagOf, run } = setup();
    const { code } = await run((service) => service.issue(admin, 7));
    const invite = await run((_, pairing) => pairing.createInvite(someone));
    await run((_, pairing) => pairing.claimInvite(reviewer, invite.code));
    expect(await tagOf((service) => service.claim(reviewer, code))).toBe("AlreadyPaired");
  });

  it("refuses an unknown, revoked, replaced or expired code as an invalid invite", async () => {
    const { tagOf, run } = setup();
    const unknown = Schema.decodeSync(ReviewCode)("ABCD2345EFGHJKLMNPQRSTUVWX");
    expect(await tagOf((service) => service.claim(reviewer, unknown))).toBe("InvalidInvite");

    const old = await run((service) => service.issue(admin, 7));
    const current = await run((service) => service.issue(admin, 7));
    expect(await tagOf((service) => service.claim(reviewer, old.code))).toBe("InvalidInvite");
    await run((service) => service.revoke(admin));
    expect(await tagOf((service) => service.claim(reviewer, current.code))).toBe("InvalidInvite");

    const expired = await Effect.runPromise(
      Effect.gen(function* () {
        const { code } = yield* (yield* ReviewService).issue(admin, 1);
        yield* TestClock.adjust(Duration.days(1));
        return yield* (yield* ReviewService).claim(reviewer, code).pipe(
          Effect.flip,
          Effect.map(({ _tag }) => _tag),
        );
      }).pipe(Effect.provide(reviewLayerOf()), Effect.provide(TestClock.layer())),
    );
    expect(expired).toBe("InvalidInvite");
  });

  it("wipes the pair: unpaired, the bot stilled, the change recorded", async () => {
    const { bots, unpaired, run } = setup();
    const { code } = await run((service) => service.issue(admin, 7));
    const pairId = await run((service) => service.claim(reviewer, code));
    await run((service) => service.wipe(admin));
    expect(unpaired).toEqual([pairId]);
    expect(bots.at(-1)).toBe(`stop ${pairId}`);
    const status = await run((service) => service.status);
    expect(status.pairId).toBeNull();
    expect(status.changes.map(({ action }) => action)).toEqual(["wipe", "issue"]);
    expect(status.codes).toMatchObject([{ live: true, claims: 1, createdBy: admin }]);
    expect(JSON.stringify(status)).not.toContain(code);
  });

  it("keeps a code's lifetime between a day and 30 days", async () => {
    const { run } = setup();
    const short = await run((service) => service.issue(admin, 0));
    const long = await run((service) => service.issue(admin, 400));
    const status = await run((service) => service.status);
    const lifetimes = status.codes.map(({ lastFour, createdAt, expiresAt }) => ({
      lastFour,
      days: (expiresAt - createdAt) / Duration.toMillis(Duration.days(1)),
    }));
    expect(lifetimes).toEqual([
      { lastFour: long.lastFour, days: 30 },
      { lastFour: short.lastFour, days: 1 },
    ]);
  });
});

/** The service on fresh fakes, for a test that brings its own clock. */
const reviewLayerOf = () => {
  const pairing = PairingService.layer.pipe(
    Layer.provide(
      Layer.mergeAll(
        Layer.succeed(PairingRepository, makeInMemoryPairingRepository().repository),
        PairingObserver.silent,
        PairMoods.none,
        Digest.layerWebCrypto,
        SecureRandom.layerWebCrypto,
      ),
    ),
  );
  return ReviewService.layer.pipe(
    Layer.provide(
      Layer.mergeAll(
        pairing,
        Layer.succeed(DemoBots, { start: () => Effect.void, stop: () => Effect.void }),
        Layer.succeed(ReviewRepository, makeInMemoryReviewRepository().repository),
        Digest.layerWebCrypto,
        SecureRandom.layerWebCrypto,
      ),
    ),
  );
};
