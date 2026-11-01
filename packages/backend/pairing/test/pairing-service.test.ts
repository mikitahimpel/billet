import { Duration, Effect, Layer, Option, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { InviteCode, UserId } from "@billet/contracts-domain/ids";
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
});
