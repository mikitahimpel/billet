import { Effect, Option, Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  type NewPurchase,
  type PaymentsRepository,
  CoinOwner,
  type StoredNotification,
  type StoredPurchase,
} from "../src/payments-repository.ts";

const owner = Schema.decodeSync(CoinOwner);

let counter = 0;
const purchaseOf = (ownerId: CoinOwner, coins = 100): NewPurchase => {
  counter += 1;
  const id = `tx-${crypto.randomUUID()}-${counter}`;
  return {
    originalTransactionId: id,
    transactionId: id,
    ownerId,
    productId: "com.ourio.app.coins.100",
    coins,
    environment: "Sandbox",
    purchasedAt: 1_700_000_000_000,
    at: 1_700_000_000_000 + counter,
  };
};

/** A time after every purchase in these tests, so ledger order is the order of the steps. */
const later = (step: number) => 2_000_000_000_000 + step;

const notificationOf = (outcome: string): StoredNotification => ({
  notificationUuid: crypto.randomUUID(),
  type: "REFUND",
  subtype: null,
  environment: "Sandbox",
  originalTransactionId: null,
  outcome,
  receivedAt: 1_700_000_100_000,
});

/** `make` returns a fresh repository, or one whose owners don't collide between tests. */
export interface ContractSubject {
  readonly repository: PaymentsRepository["Service"];
  /** Coins are spent in the app, so only a test can make the server's balance smaller than a
   * purchase it refunds. */
  readonly spend: (owner: CoinOwner, coins: number) => Promise<void>;
}

export const paymentsRepositoryContract = (label: string, make: () => Promise<ContractSubject>) =>
  describe(`${label} PaymentsRepository`, () => {
    const run = <A, E>(effect: Effect.Effect<A, E>) => Effect.runPromise(effect);
    const stored = async (repository: PaymentsRepository["Service"], id: string) =>
      Option.getOrThrow(await run(repository.findPurchase(id))) as StoredPurchase;

    it("credits a purchase once", async () => {
      const { repository } = await make();
      const pair = owner(`pair-${crypto.randomUUID()}`);
      const purchase = purchaseOf(pair);
      expect(await run(repository.credit(purchase))).toEqual({ duplicate: false, balance: 100 });
      expect(await run(repository.credit(purchase))).toEqual({ duplicate: true, balance: 100 });
      const ledger = await run(repository.ledger(pair));
      expect(ledger.balance).toBe(100);
      expect(ledger.entries.map(({ id, kind, amount }) => ({ id, kind, amount }))).toEqual([
        { id: `purchase:${purchase.originalTransactionId}`, kind: "purchase", amount: 100 },
      ]);
    });

    it("never credits another owner's transaction", async () => {
      const { repository } = await make();
      const [first, second] = [
        owner(`pair-${crypto.randomUUID()}`),
        owner(`pair-${crypto.randomUUID()}`),
      ];
      const purchase = purchaseOf(first);
      await run(repository.credit(purchase));
      expect(await run(repository.credit({ ...purchase, ownerId: second }))).toEqual({
        duplicate: true,
        balance: 0,
      });
      expect((await run(repository.ledger(second))).entries).toEqual([]);
    });

    it("refunds, restores and refunds again, with stable entry ids", async () => {
      const { repository } = await make();
      const pair = owner(`pair-${crypto.randomUUID()}`);
      const purchase = purchaseOf(pair);
      const id = purchase.originalTransactionId;
      await run(repository.credit(purchase));
      await run(repository.credit(purchaseOf(pair, 550)));

      const refunded = await run(repository.refund(await stored(repository, id), later(2)));
      expect(refunded).toEqual({ duplicate: false, coins: 100, balance: 550 });
      // The same refund again, from the state read before it, changes nothing.
      expect(
        (
          await run(
            repository.refund(
              { ...(await stored(repository, id)), status: "credited", refunds: 0 },
              later(3),
            ),
          )
        ).duplicate,
      ).toBe(true);
      expect((await run(repository.refund(await stored(repository, id), later(3)))).duplicate).toBe(
        true,
      );

      expect(await run(repository.restore(await stored(repository, id), later(4)))).toEqual({
        duplicate: false,
        coins: 100,
        balance: 650,
      });
      expect(
        (await run(repository.restore(await stored(repository, id), later(5)))).duplicate,
      ).toBe(true);
      expect((await run(repository.refund(await stored(repository, id), later(6)))).coins).toBe(
        100,
      );

      const ledger = await run(repository.ledger(pair));
      expect(ledger.balance).toBe(550);
      expect(ledger.entries.map(({ id: entry, amount }) => [entry, amount])).toEqual([
        [`purchase:${id}`, 100],
        [expect.stringMatching(/^purchase:/), 550],
        [`refund:${id}`, -100],
        [`restore:${id}`, 100],
        [`refund:${id}:2`, -100],
      ]);
      const after = await stored(repository, id);
      expect({ status: after.status, refunds: after.refunds, flagged: after.flagged }).toEqual({
        status: "refunded",
        refunds: 2,
        flagged: 0,
      });
    });

    it("takes back the whole pack even when it was spent, and flags a refund that leaves a debt", async () => {
      const { repository, spend } = await make();
      const pair = owner(`pair-${crypto.randomUUID()}`);
      const purchase = purchaseOf(pair, 100);
      const id = purchase.originalTransactionId;
      await run(repository.credit(purchase));
      await spend(pair, 70);

      expect(
        await run(repository.refund(await stored(repository, id), later(2), undefined, true)),
      ).toEqual({ duplicate: false, coins: 100, balance: -70 });
      const after = await stored(repository, id);
      expect({ status: after.status, flagged: after.flagged }).toEqual({
        status: "refunded",
        flagged: 1,
      });
      const ledger = await run(repository.ledger(pair));
      expect(ledger.entries.find(({ id: entry }) => entry === `refund:${id}`)?.amount).toBe(-100);

      expect(await run(repository.restore(after, later(3)))).toEqual({
        duplicate: false,
        coins: 100,
        balance: 30,
      });
    });

    it("records a notification once", async () => {
      const { repository } = await make();
      const notification = notificationOf("recorded");
      expect(await run(repository.hasNotification(notification.notificationUuid))).toBe(false);
      await run(repository.recordNotification(notification));
      await run(repository.recordNotification({ ...notification, outcome: "again" }));
      expect(await run(repository.hasNotification(notification.notificationUuid))).toBe(true);
    });

    it("records a notification with a refund, even when the refund changes nothing", async () => {
      const { repository } = await make();
      const pair = owner(`pair-${crypto.randomUUID()}`);
      const purchase = purchaseOf(pair);
      await run(repository.credit(purchase));
      const first = notificationOf("refunded");
      await run(
        repository.refund(
          await stored(repository, purchase.originalTransactionId),
          later(2),
          first,
        ),
      );
      const second = notificationOf("duplicate");
      const again = await run(
        repository.refund(
          await stored(repository, purchase.originalTransactionId),
          later(3),
          second,
        ),
      );
      expect(again.duplicate).toBe(true);
      expect(await run(repository.hasNotification(first.notificationUuid))).toBe(true);
      expect(await run(repository.hasNotification(second.notificationUuid))).toBe(true);
    });
  });
