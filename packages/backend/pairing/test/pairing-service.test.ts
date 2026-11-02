import { Duration, Effect, Layer, Option, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { InviteCode, UserId } from "@billet/contracts-domain/ids";
import { PairingObserver } from "../src/pairing-observer.ts";
import { PairingRepository } from "../src/pairing-repository.ts";
import { inviteLifetime, PairingService } from "../src/pairing-service.ts";
import { makeInMemoryPairingRepository } from "./in-memory-pairing-repository.ts";

const user = Schema.decodeSync(UserId);
const ana = user("user-a");
const ben = user("user-b");

const setup = () => {
  const memory = makeInMemoryPairingRepository();
  const layer = PairingService.layer.pipe(
    Layer.provide(
      Layer.mergeAll(
        Layer.succeed(PairingRepository, memory.repository),
        PairingObserver.silent,
        Digest.layerWebCrypto,
        SecureRandom.layerWebCrypto,
      ),
    ),
  );
  const run = <A, E>(use: (service: PairingService["Service"]) => Effect.Effect<A, E>) =>
    Effect.runPromise(
      Effect.gen(function* () {
        return yield* use(yield* PairingService);
      }).pipe(Effect.provide(layer)),
    );
  return { memory, layer, run };
};

describe("PairingService", () => {
  it("issues well-formed codes that differ", async () => {
    const { run } = setup();
    const codes = await Promise.all(
      Array.from({ length: 50 }, (_, index) =>
        run((service) => service.createInvite(user(`user-${index}`))),
      ),
    );
    const isCode = Schema.is(InviteCode);
    expect(codes.every(({ code }) => isCode(code))).toBe(true);
    expect(new Set(codes.map(({ code }) => code)).size).toBe(50);
  });

  it("reports the expiry it enforces: the moment the code stops working", async () => {
    const claimAt = (offset: number) =>
      Effect.runPromise(
        Effect.gen(function* () {
          const service = yield* PairingService;
          yield* TestClock.adjust(Duration.seconds(10));
          const { code, expiresAt } = yield* service.createInvite(ana);
          // The clock reads ten seconds, so the invite was made at 10_000 ms.
          const untilExpiry = expiresAt - 10_000;
          yield* TestClock.adjust(Duration.millis(untilExpiry + offset));
          return { expiresAt, claimed: yield* service.claimInvite(ben, code).pipe(Effect.exit) };
        }).pipe(Effect.provide(setup().layer), Effect.provide(TestClock.layer())),
      );
    const before = await claimAt(-1);
    expect(before.expiresAt).toBe(10_000 + Duration.toMillis(inviteLifetime));
    expect(before.claimed._tag).toBe("Success");
    expect((await claimAt(0)).claimed._tag).toBe("Failure");
  });

  it("pairs two users with a code, under one new pair id", async () => {
    const { memory, run } = setup();
    const { code } = await run((service) => service.createInvite(ana));
    const pairId = await run((service) => service.claimInvite(ben, code));
    const found = await Effect.runPromise(memory.repository.findPair(ana));
    expect(found).toEqual(Option.some(pairId));
  });

  it("stores only a hash of the code", async () => {
    const { memory, run } = setup();
    const { code } = await run((service) => service.createInvite(ana));
    expect(await Effect.runPromise(memory.dump)).not.toContain(code);
  });

  it("expires a code when its lifetime ends, and not before", async () => {
    const claimAfter = (elapsed: Duration.Duration) =>
      Effect.runPromise(
        Effect.gen(function* () {
          const service = yield* PairingService;
          const { code } = yield* service.createInvite(ana);
          yield* TestClock.adjust(elapsed);
          return yield* service.claimInvite(ben, code);
        }).pipe(
          Effect.as("claimed"),
          Effect.catch(({ _tag }) => Effect.succeed(_tag)),
          Effect.provide(setup().layer),
          Effect.provide(TestClock.layer()),
        ),
      );
    expect(await claimAfter(Duration.subtract(inviteLifetime, Duration.millis(1)))).toBe("claimed");
    expect(await claimAfter(inviteLifetime)).toBe("InvalidInvite");
  });

  it("unpairs through the repository", async () => {
    const { memory, run } = setup();
    const { code } = await run((service) => service.createInvite(ana));
    await run((service) => service.claimInvite(ben, code));
    await run((service) => service.unpair(ben));
    expect(await Effect.runPromise(memory.repository.findPair(ana))).toEqual(Option.none());
  });

  describe("observer", () => {
    const observed = () => {
      const calls: Array<string> = [];
      const memory = makeInMemoryPairingRepository();
      const layer = PairingService.layer.pipe(
        Layer.provide(
          Layer.mergeAll(
            Layer.succeed(PairingRepository, memory.repository),
            Layer.succeed(PairingObserver, {
              invited: (userId) => Effect.sync(() => void calls.push(`invited ${userId}`)),
              paired: (pairId, members) =>
                Effect.sync(
                  () => void calls.push(`paired ${pairId} ${members.toSorted().join(",")}`),
                ),
            }),
            Digest.layerWebCrypto,
            SecureRandom.layerWebCrypto,
          ),
        ),
      );
      return { calls, layer };
    };

    it("hears about an invite and about a pairing, with both members", async () => {
      const { calls, layer } = observed();
      const pairId = await Effect.runPromise(
        Effect.gen(function* () {
          const service = yield* PairingService;
          const { code } = yield* service.createInvite(ana);
          return yield* service.claimInvite(ben, code);
        }).pipe(Effect.provide(layer)),
      );
      expect(calls).toEqual([`invited ${ana}`, `paired ${pairId} ${ana},${ben}`]);
    });

    it("does not hear about a claim that failed", async () => {
      const { calls, layer } = observed();
      const code = Schema.decodeSync(InviteCode)("ABCD2345EF");
      await Effect.runPromise(
        Effect.gen(function* () {
          const service = yield* PairingService;
          yield* service.claimInvite(ben, code).pipe(Effect.ignore);
        }).pipe(Effect.provide(layer)),
      );
      expect(calls).toEqual([]);
    });

    it("still pairs when the observer fails or dies", async () => {
      const memory = makeInMemoryPairingRepository();
      const layer = PairingService.layer.pipe(
        Layer.provide(
          Layer.mergeAll(
            Layer.succeed(PairingRepository, memory.repository),
            Layer.succeed(PairingObserver, {
              invited: () => Effect.die("observer is down"),
              paired: () => Effect.die("observer is down"),
            }),
            Digest.layerWebCrypto,
            SecureRandom.layerWebCrypto,
          ),
        ),
      );
      const pairId = await Effect.runPromise(
        Effect.gen(function* () {
          const service = yield* PairingService;
          const { code } = yield* service.createInvite(ana);
          return yield* service.claimInvite(ben, code);
        }).pipe(Effect.provide(layer)),
      );
      expect(Option.getOrUndefined(await Effect.runPromise(memory.repository.findPair(ben)))).toBe(
        pairId,
      );
    });
  });
});
