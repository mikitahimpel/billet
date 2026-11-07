import { Effect, Option, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import type { InviteClaim, PairingRepository, StoredInvite } from "../src/pairing-repository.ts";

const user = Schema.decodeSync(UserId);
const pair = Schema.decodeSync(PairId);

export const contractUsers = ["user-a", "user-b", "user-c", "user-d"] as const;

const [ana, ben, cal, dee] = contractUsers.map((id) => user(id)) as [
  UserId,
  UserId,
  UserId,
  UserId,
];

const invite = (ownerId: UserId, overrides: Partial<StoredInvite> = {}): StoredInvite => ({
  codeHash: `hash-${ownerId}`,
  ownerId,
  createdAt: 1_000,
  expiresAt: 2_000,
  ...overrides,
});

const claim = (
  claimerId: UserId,
  owner: UserId,
  overrides: Partial<InviteClaim> = {},
): InviteClaim => ({
  codeHash: `hash-${owner}`,
  claimerId,
  pairId: pair(`pair-${claimerId}-${owner}`),
  now: 1_500,
  ...overrides,
});

const failureOf = <A, E extends { readonly _tag: string }>(effect: Effect.Effect<A, E>) =>
  effect.pipe(
    Effect.flip,
    Effect.map(({ _tag }) => _tag),
  );

/**
 * The behaviour every `PairingRepository` must have. Run it against each implementation, so the
 * in-memory fake can't drift from the real one. `make` must return an empty repository in which
 * `contractUsers` exist.
 */
export const describePairingRepositoryContract = (
  name: string,
  make: () => Promise<PairingRepository["Service"]>,
): void => {
  describe(`PairingRepository contract: ${name}`, () => {
    it("pairs the claimer with the invite's owner", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.claimInvite(claim(ben, ana));
          return [yield* repository.findPair(ana), yield* repository.findPair(ben)];
        }),
      );
      expect(found).toEqual([Option.some("pair-user-b-user-a"), Option.some("pair-user-b-user-a")]);
    });

    it("lets a code be claimed once", async () => {
      const repository = await make();
      const failure = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.claimInvite(claim(ben, ana));
          return yield* failureOf(repository.claimInvite(claim(cal, ana)));
        }),
      );
      expect(failure).toBe("InvalidInvite");
      expect(await Effect.runPromise(repository.findPair(cal))).toEqual(Option.none());
    });

    it("refuses an unknown code, an expired one and the caller's own", async () => {
      const repository = await make();
      const [unknown, expired, own, found] = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          return [
            yield* failureOf(repository.claimInvite(claim(ben, cal))),
            yield* failureOf(repository.claimInvite(claim(ben, ana, { now: 2_000 }))),
            yield* failureOf(repository.claimInvite(claim(ana, ana))),
            yield* repository.findPair(ana),
          ] as const;
        }),
      );
      expect([unknown, expired, own]).toEqual(["InvalidInvite", "InvalidInvite", "InvalidInvite"]);
      expect(found).toEqual(Option.none());
    });

    it("keeps an invite usable after a refused claim of it", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* failureOf(repository.claimInvite(claim(ana, ana)));
          yield* repository.claimInvite(claim(ben, ana));
          return yield* repository.findPair(ana);
        }),
      );
      expect(Option.isSome(found)).toBe(true);
    });

    it("refuses a paired user another code, and that code stays claimable", async () => {
      const repository = await make();
      const [failure, kept, partner] = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.saveInvite(invite(cal));
          yield* repository.claimInvite(claim(ben, ana));
          const refused = yield* failureOf(repository.claimInvite(claim(ben, cal)));
          const before = yield* repository.findPair(ben);
          yield* repository.claimInvite(claim(dee, cal));
          return [refused, before, yield* repository.findPair(cal)] as const;
        }),
      );
      expect(failure).toBe("AlreadyPaired");
      expect(kept).toEqual(Option.some("pair-user-b-user-a"));
      expect(partner).toEqual(Option.some("pair-user-d-user-c"));
    });

    it("refuses the owner of a code too, once paired", async () => {
      const repository = await make();
      const failure = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.saveInvite(invite(cal));
          yield* repository.claimInvite(claim(ben, ana));
          return yield* failureOf(repository.claimInvite(claim(ana, cal)));
        }),
      );
      expect(failure).toBe("AlreadyPaired");
    });

    it("refuses a paired user a new invite", async () => {
      const repository = await make();
      const failures = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.claimInvite(claim(ben, ana));
          return [
            yield* failureOf(repository.saveInvite(invite(ana, { codeHash: "new-a" }))),
            yield* failureOf(repository.saveInvite(invite(ben, { codeHash: "new-b" }))),
          ];
        }),
      );
      expect(failures).toEqual(["AlreadyPaired", "AlreadyPaired"]);
    });

    it("removes the claimer's own invite when it pairs", async () => {
      const repository = await make();
      const failure = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.saveInvite(invite(ben));
          yield* repository.claimInvite(claim(ben, ana));
          return yield* failureOf(repository.claimInvite(claim(cal, ben)));
        }),
      );
      expect(failure).toBe("InvalidInvite");
    });

    it("replaces the owner's earlier invite", async () => {
      const repository = await make();
      const failure = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana, { codeHash: "old" }));
          yield* repository.saveInvite(invite(ana, { codeHash: "new" }));
          const refused = yield* failureOf(
            repository.claimInvite(claim(ben, ana, { codeHash: "old" })),
          );
          yield* repository.claimInvite(claim(ben, ana, { codeHash: "new" }));
          return refused;
        }),
      );
      expect(failure).toBe("InvalidInvite");
    });

    it("removes expired invites when saving one, and keeps live ones", async () => {
      const repository = await make();
      const [expired, live] = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.saveInvite(invite(ben, { expiresAt: 4_000 }));
          yield* repository.saveInvite(invite(cal, { createdAt: 3_000, expiresAt: 5_000 }));
          return [
            // Claimed at an earlier time, so only a real delete can make the first one disappear.
            yield* failureOf(repository.claimInvite(claim(dee, ana))),
            yield* repository.claimInvite(claim(dee, ben)).pipe(Effect.as("claimed")),
          ];
        }),
      );
      expect(expired).toBe("InvalidInvite");
      expect(live).toBe("claimed");
    });

    it("clears the lookup of both partners on unpair, from either side", async () => {
      const repository = await make();
      const [before, after] = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.claimInvite(claim(ben, ana));
          const paired = yield* repository.findPair(ana);
          yield* repository.unpair(ben);
          return [
            paired,
            [yield* repository.findPair(ana), yield* repository.findPair(ben)],
          ] as const;
        }),
      );
      expect(Option.isSome(before)).toBe(true);
      expect(after).toEqual([Option.none(), Option.none()]);
    });

    it("knows when a pair formed, and forgets it once the pair has ended", async () => {
      const repository = await make();
      const pairId = pair("pair-user-b-user-a");
      const [unknown, before, after] = await Effect.runPromise(
        Effect.gen(function* () {
          const unknown = yield* repository.pairedAt(pairId);
          yield* repository.saveInvite(invite(ana));
          yield* repository.claimInvite(claim(ben, ana, { now: 1_700 }));
          const formed = yield* repository.pairedAt(pairId);
          yield* repository.unpair(ben);
          return [unknown, formed, yield* repository.pairedAt(pairId)] as const;
        }),
      );
      expect(unknown).toEqual(Option.none());
      expect(before).toEqual(Option.some(1_700));
      expect(after).toEqual(Option.none());
    });

    it("finds both members of a pair, and nobody once it has ended", async () => {
      const repository = await make();
      const pairId = pair("pair-user-b-user-a");
      const [before, after] = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.claimInvite(claim(ben, ana));
          const members = yield* repository.findMembers(pairId);
          yield* repository.unpair(ana);
          return [members, yield* repository.findMembers(pairId)] as const;
        }),
      );
      expect(before.toSorted()).toEqual([ana, ben]);
      expect(after).toEqual([]);
    });

    it("leaves other pairs alone on unpair, and does nothing for an unpaired user", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.saveInvite(invite(cal));
          yield* repository.claimInvite(claim(ben, ana));
          yield* repository.claimInvite(claim(dee, cal));
          yield* repository.unpair(ana);
          yield* repository.unpair(ana);
          return [yield* repository.findPair(cal), yield* repository.findPair(dee)];
        }),
      );
      expect(found).toEqual([Option.some("pair-user-d-user-c"), Option.some("pair-user-d-user-c")]);
    });

    it("blocks: ends the pair and refuses a new claim either way round", async () => {
      const repository = await make();
      const result = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.claimInvite(claim(ben, ana));
          yield* repository.block({ blocker: ana, blocked: ben, at: 1_600 });
          yield* repository.block({ blocker: ana, blocked: ben, at: 1_700 });
          const found = yield* repository.findPair(ben);
          yield* repository.saveInvite(invite(ana));
          const byBlocked = yield* failureOf(repository.claimInvite(claim(ben, ana)));
          yield* repository.saveInvite(invite(ben));
          const byBlocker = yield* failureOf(repository.claimInvite(claim(ana, ben)));
          yield* repository.saveInvite(invite(cal));
          yield* repository.claimInvite(claim(ben, cal));
          return { found, byBlocked, byBlocker, other: yield* repository.findPair(ben) };
        }),
      );
      expect(result.found).toEqual(Option.none());
      expect(result.byBlocked).toBe("InvalidInvite");
      expect(result.byBlocker).toBe("InvalidInvite");
      expect(result.other).toEqual(Option.some("pair-user-b-user-c"));
    });

    it("keeps a report without touching the pair", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.claimInvite(claim(ben, ana));
          yield* repository.saveReport({
            id: "report-1",
            reporter: ana,
            reported: ben,
            pairId: pair("pair-user-b-user-a"),
            reason: "spam",
            details: undefined,
            at: 1_600,
          });
          return yield* repository.findPair(ana);
        }),
      );
      expect(found).toEqual(Option.some("pair-user-b-user-a"));
    });

    it("lets former partners pair again, under a new pair id", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveInvite(invite(ana));
          yield* repository.claimInvite(claim(ben, ana));
          yield* repository.unpair(ana);
          yield* repository.saveInvite(invite(ana));
          yield* repository.claimInvite(claim(ben, ana, { pairId: pair("second-pair") }));
          return yield* repository.findPair(ana);
        }),
      );
      expect(found).toEqual(Option.some("second-pair"));
    });
  });
};
