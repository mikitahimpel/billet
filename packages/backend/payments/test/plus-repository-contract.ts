import { Effect, Option, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import type {
  PlusRepository,
  StoredParcel,
  StoredPeriod,
  StoredSubscription,
} from "../src/plus-repository.ts";

const user = Schema.decodeSync(UserId);
const pair = Schema.decodeSync(PairId);

const subscriptionOf = (userId: UserId, id: string): StoredSubscription => ({
  originalTransactionId: id,
  userId,
  productId: "com.ourio.app.plus.monthly",
  environment: "Sandbox",
  expiresAt: 1_800_000_000_000,
  autoRenew: true,
  graceUntil: null,
  revokedAt: null,
  createdAt: 1_700_000_000_000,
  updatedAt: 1_700_000_000_000,
});

const periodOf = (userId: UserId, otid: string, id: string): StoredPeriod => ({
  transactionId: id,
  originalTransactionId: otid,
  userId,
  productId: "com.ourio.app.plus.monthly",
  purchasedAt: 1_700_000_000_000,
  expiresAt: 1_702_600_000_000,
  revokedAt: null,
});

const parcelOf = (payer: UserId, transactionId: string, offer: string): StoredParcel => ({
  id: `parcel:${transactionId}`,
  payer,
  transactionId,
  pairId: pair(`pair-${crypto.randomUUID()}`),
  offer,
  price: 90,
  openedBy: payer,
  openedAt: 1_700_000_100_000,
  status: "opened",
});

/** `make` returns a repository; ids are fresh per test, so one may be shared. */
export const plusRepositoryContract = (
  label: string,
  make: () => Promise<PlusRepository["Service"]>,
) =>
  describe(`${label} PlusRepository`, () => {
    const run = <A, E>(effect: Effect.Effect<A, E>) => Effect.runPromise(effect);
    const fresh = () => crypto.randomUUID();

    it("binds a subscription to its first account and never to another", async () => {
      const repository = await make();
      const [first, second] = [user(`u-${fresh()}`), user(`u-${fresh()}`)];
      const id = fresh();
      const stored = await run(repository.saveSubscription(subscriptionOf(first, id)));
      expect(stored.userId).toBe(first);
      const taken = await run(
        repository.saveSubscription({ ...subscriptionOf(second, id), autoRenew: false }),
      );
      expect(taken).toEqual(subscriptionOf(first, id));
      const changed = await run(
        repository.saveSubscription({
          ...subscriptionOf(first, id),
          autoRenew: false,
          graceUntil: 1_800_000_000_001,
          updatedAt: 1_700_000_000_009,
        }),
      );
      expect(changed.autoRenew).toBe(false);
      expect(Option.getOrThrow(await run(repository.findSubscription(id)))).toEqual(changed);
      expect(Option.isNone(await run(repository.findSubscription(fresh())))).toBe(true);
    });

    it("stores a period once, changing only whether it was refunded", async () => {
      const repository = await make();
      const payer = user(`u-${fresh()}`);
      const otid = fresh();
      const period = periodOf(payer, otid, fresh());
      await run(repository.savePeriod(period));
      await run(repository.savePeriod({ ...period, purchasedAt: 1, revokedAt: 1_700_000_500_000 }));
      const { periods } = await run(repository.recordsOf([payer]));
      expect(periods).toEqual([{ ...period, revokedAt: 1_700_000_500_000 }]);
      await run(repository.savePeriod({ ...period, revokedAt: null }));
      expect((await run(repository.recordsOf([payer]))).periods).toEqual([period]);
    });

    it("opens a parcel once and answers the first open to a second", async () => {
      const repository = await make();
      const payer = user(`u-${fresh()}`);
      const transactionId = fresh();
      const first = parcelOf(payer, transactionId, '{"_tag":"Item","item":"yarn"}');
      expect(await run(repository.openParcel(first))).toEqual(first);
      const second = { ...first, offer: '{"_tag":"Item","item":"rug"}' };
      expect(await run(repository.openParcel(second))).toEqual(first);
      expect(await run(repository.parcelsOfTransaction(transactionId))).toEqual([first]);
      await run(repository.setParcelStatus(first.id, "refunded"));
      expect((await run(repository.recordsOf([payer]))).parcels).toEqual([
        { ...first, status: "refunded" },
      ]);
    });

    it("reads only the accounts asked for", async () => {
      const repository = await make();
      const [mine, theirs, stranger] = [
        user(`u-${fresh()}`),
        user(`u-${fresh()}`),
        user(`u-${fresh()}`),
      ];
      for (const owner of [mine, theirs, stranger]) {
        const otid = fresh();
        await run(repository.saveSubscription(subscriptionOf(owner, otid)));
        await run(repository.savePeriod(periodOf(owner, otid, fresh())));
      }
      const records = await run(repository.recordsOf([mine, theirs]));
      expect(records.subscriptions.map(({ userId }) => userId).toSorted()).toEqual(
        [mine, theirs].toSorted(),
      );
      expect(records.periods).toHaveLength(2);
    });
  });
