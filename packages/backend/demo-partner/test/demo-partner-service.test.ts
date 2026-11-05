import { Effect, Layer, Option, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { describe, expect, it } from "vitest";
import { AccountDeletion } from "@billet/backend-account/account-deletion";
import { PairingObserver } from "@billet/backend-pairing/pairing-observer";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { PairingService } from "@billet/backend-pairing/pairing-service";
import { makeInMemoryPairingRepository } from "@billet/backend-pairing/test/in-memory-pairing-repository";
import { UserId } from "@billet/contracts-domain/ids";
import { DemoPartnerRepository } from "../src/demo-partner-repository.ts";
import { DemoPartnerService } from "../src/demo-partner-service.ts";
import { makeInMemoryDemoPartnerRepository } from "./in-memory-demo-partner-repository.ts";

const user = Schema.decodeSync(UserId);
const ana = user("user-a");
const ben = user("user-b");

const setup = () => {
  const pairs = makeInMemoryPairingRepository().repository;
  const demos = makeInMemoryDemoPartnerRepository();
  const paired: Array<{ members: ReadonlyArray<UserId>; claimer: UserId }> = [];
  const unpaired: Array<string> = [];
  // What the real deletion would see: whether each deleted user was still in a pair, and with whom.
  const deleted: Array<{ userId: UserId; partnered: boolean }> = [];

  const observer = Layer.succeed(PairingObserver, {
    invited: () => Effect.void,
    paired: (_, members, { claimer }) => Effect.sync(() => paired.push({ members, claimer })),
    unpaired: (pairId) => Effect.sync(() => unpaired.push(pairId)),
  });
  const deletion = Layer.succeed(AccountDeletion, {
    deleteAccount: (userId) =>
      Effect.gen(function* () {
        const pair = yield* Effect.orDie(pairs.findPair(userId));
        deleted.push({ userId, partnered: Option.isSome(pair) });
        yield* Effect.orDie(pairs.unpair(userId));
      }),
  });
  const pairing = PairingService.layer.pipe(
    Layer.provide(
      Layer.mergeAll(
        Layer.succeed(PairingRepository, pairs),
        observer,
        Digest.layerWebCrypto,
        SecureRandom.layerWebCrypto,
      ),
    ),
  );
  const layer = Layer.mergeAll(
    DemoPartnerService.layer.pipe(
      Layer.provide(
        Layer.mergeAll(
          pairing,
          deletion,
          Layer.succeed(DemoPartnerRepository, demos.repository),
          SecureRandom.layerWebCrypto,
        ),
      ),
    ),
    pairing,
  );
  const run = <A, E>(
    use: (
      demo: DemoPartnerService["Service"],
      pairing: PairingService["Service"],
    ) => Effect.Effect<A, E>,
  ) =>
    Effect.runPromise(
      Effect.gen(function* () {
        return yield* use(yield* DemoPartnerService, yield* PairingService);
      }).pipe(Effect.provide(layer)),
    );
  const tagOf = <A, E extends { readonly _tag: string }>(
    use: (
      demo: DemoPartnerService["Service"],
      pairing: PairingService["Service"],
    ) => Effect.Effect<A, E>,
  ) =>
    run((demo, pairing) =>
      use(demo, pairing).pipe(
        Effect.flip,
        Effect.map(({ _tag }) => _tag),
      ),
    );
  return { demos, paired, unpaired, deleted, run, tagOf };
};

describe("DemoPartnerService", () => {
  it("pairs the caller with a new bot through an invite, the caller first", async () => {
    const { demos, paired, run } = setup();
    const created = await run((demo) => demo.create(ana));
    const [, bot] = created.members;
    expect(created.members[0]).toBe(ana);
    expect(bot).not.toBe(ana);
    expect(await run((_, pairing) => pairing.pair(ana))).toEqual(created);
    expect(paired).toEqual([{ members: expect.arrayContaining([ana, bot]), claimer: ana }]);
    expect([...demos.bots]).toEqual([bot]);
  });

  it("gives each caller a bot of its own", async () => {
    const { run } = setup();
    const first = await run((demo) => demo.create(ana));
    const second = await run((demo) => demo.create(ben));
    expect(first.members[1]).not.toBe(second.members[1]);
    expect(first.pairId).not.toBe(second.pairId);
  });

  it("refuses a caller who already has a partner, and makes no bot", async () => {
    const { demos, tagOf, run } = setup();
    await run((_, pairing) =>
      pairing.createInvite(ana).pipe(Effect.flatMap(({ code }) => pairing.claimInvite(ben, code))),
    );
    expect(await tagOf((demo) => demo.create(ana))).toBe("AlreadyPaired");
    expect(demos.bots.size).toBe(0);
  });

  it("refuses a second bot while the first is the caller's partner", async () => {
    const { demos, tagOf, run } = setup();
    await run((demo) => demo.create(ana));
    expect(await tagOf((demo) => demo.create(ana))).toBe("AlreadyPaired");
    expect(demos.bots.size).toBe(1);
  });

  it("unpairs the caller before deleting the bot, and forgets it", async () => {
    const { demos, deleted, unpaired, run, tagOf } = setup();
    const { pairId, members } = await run((demo) => demo.create(ana));
    await run((demo) => demo.remove(ana));
    expect(unpaired).toEqual([pairId]);
    expect(deleted).toEqual([{ userId: members[1], partnered: false }]);
    expect(await Effect.runPromise(demos.repository.botOf(ana))).toEqual(Option.none());
    expect(await tagOf((_, pairing) => pairing.pair(ana))).toBe("NotPaired");
  });

  it("answers NoDemoPartner to a caller without a bot", async () => {
    const { tagOf } = setup();
    expect(await tagOf((demo) => demo.remove(ana))).toBe("NoDemoPartner");
  });

  it("deletes a bot the caller left another way, before making a new one", async () => {
    const { deleted, run } = setup();
    const first = await run((demo) => demo.create(ana));
    await run((_, pairing) => pairing.unpair(ana));
    const second = await run((demo) => demo.create(ana));
    expect(deleted).toEqual([{ userId: first.members[1], partnered: false }]);
    expect(second.members[1]).not.toBe(first.members[1]);
  });

  it("keeps a real partner when it deletes a bot the caller left", async () => {
    const { deleted, unpaired, run } = setup();
    const { members } = await run((demo) => demo.create(ana));
    await run((_, pairing) => pairing.unpair(ana));
    const pairId = await run((_, pairing) =>
      pairing.createInvite(ben).pipe(Effect.flatMap(({ code }) => pairing.claimInvite(ana, code))),
    );
    await run((demo) => demo.remove(ana));
    expect(deleted).toEqual([{ userId: members[1], partnered: false }]);
    expect(unpaired).toHaveLength(1);
    expect((await run((_, pairing) => pairing.pair(ana))).pairId).toBe(pairId);
  });
});
