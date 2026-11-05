import { Effect, Option } from "effect";
import {
  entryIds,
  type PaymentsRepository,
  type CoinOwner,
  type StoredNotification,
  type StoredPurchase,
  type StoredPurchaseEntry,
} from "../src/payments-repository.ts";

export interface InMemoryPaymentsRepository {
  readonly repository: PaymentsRepository["Service"];
  readonly notifications: () => ReadonlyArray<StoredNotification>;
  /** A negative entry, as spending coins on the server would write. Tests only. */
  readonly spend: (owner: CoinOwner, coins: number) => Promise<void>;
}

/** The test double for `PaymentsRepository`. Single-threaded, so each method is trivially atomic. */
export const makeInMemoryPaymentsRepository = (): InMemoryPaymentsRepository => {
  const purchases = new Map<string, StoredPurchase>();
  const entries: StoredPurchaseEntry[] = [];
  const notifications = new Map<string, StoredNotification>();

  const balanceOf = (owner: CoinOwner) =>
    Math.max(
      0,
      entries
        .filter(({ ownerId }) => ownerId === owner)
        .reduce((sum, { amount }) => sum + amount, 0),
    );

  const note = (notification: StoredNotification | undefined) => {
    if (notification !== undefined && !notifications.has(notification.notificationUuid)) {
      notifications.set(notification.notificationUuid, notification);
    }
  };

  const unchanged = (purchase: StoredPurchase) => {
    const current = purchases.get(purchase.originalTransactionId);
    return current !== undefined &&
      current.status === purchase.status &&
      current.refunds === purchase.refunds
      ? current
      : undefined;
  };

  const repository: PaymentsRepository["Service"] = {
    credit: (purchase) =>
      Effect.sync(() => {
        if (purchases.has(purchase.originalTransactionId)) {
          return { duplicate: true, balance: balanceOf(purchase.ownerId) };
        }
        purchases.set(purchase.originalTransactionId, {
          originalTransactionId: purchase.originalTransactionId,
          transactionId: purchase.transactionId,
          ownerId: purchase.ownerId,
          productId: purchase.productId,
          coins: purchase.coins,
          environment: purchase.environment,
          status: "credited",
          refunds: 0,
          flagged: 0,
          purchasedAt: purchase.purchasedAt,
          createdAt: purchase.at,
          updatedAt: purchase.at,
        });
        entries.push({
          id: entryIds.purchase(purchase.originalTransactionId),
          ownerId: purchase.ownerId,
          kind: "purchase",
          amount: purchase.coins,
          productId: purchase.productId,
          originalTransactionId: purchase.originalTransactionId,
          at: purchase.at,
        });
        return { duplicate: false, balance: balanceOf(purchase.ownerId) };
      }),
    findPurchase: (id) => Effect.sync(() => Option.fromNullishOr(purchases.get(id))),
    refund: (purchase, at, notification) =>
      Effect.sync(() => {
        note(notification);
        const current = unchanged(purchase);
        if (current === undefined || current.status !== "credited") {
          return { duplicate: true, coins: 0, balance: balanceOf(purchase.ownerId) };
        }
        const taken = Math.min(current.coins, balanceOf(current.ownerId));
        const refunds = current.refunds + 1;
        entries.push({
          id: entryIds.refund(current.originalTransactionId, refunds),
          ownerId: current.ownerId,
          kind: "refund",
          amount: -taken,
          productId: current.productId,
          originalTransactionId: current.originalTransactionId,
          at,
        });
        purchases.set(current.originalTransactionId, {
          ...current,
          status: "refunded",
          refunds,
          flagged: taken < current.coins ? 1 : current.flagged,
          updatedAt: at,
        });
        return { duplicate: false, coins: taken, balance: balanceOf(current.ownerId) };
      }),
    restore: (purchase, at, notification) =>
      Effect.sync(() => {
        note(notification);
        const current = unchanged(purchase);
        if (current === undefined || current.status !== "refunded") {
          return { duplicate: true, coins: 0, balance: balanceOf(purchase.ownerId) };
        }
        const refundId = entryIds.refund(current.originalTransactionId, current.refunds);
        const given = -(entries.find(({ id }) => id === refundId)?.amount ?? 0);
        entries.push({
          id: entryIds.restore(current.originalTransactionId, current.refunds),
          ownerId: current.ownerId,
          kind: "purchase",
          amount: given,
          productId: current.productId,
          originalTransactionId: current.originalTransactionId,
          at,
        });
        purchases.set(current.originalTransactionId, {
          ...current,
          status: "credited",
          updatedAt: at,
        });
        return { duplicate: false, coins: given, balance: balanceOf(current.ownerId) };
      }),
    hasNotification: (uuid) => Effect.sync(() => notifications.has(uuid)),
    recordNotification: (notification) => Effect.sync(() => note(notification)),
    ledger: (owner) =>
      Effect.sync(() => ({
        balance: balanceOf(owner),
        entries: entries.filter(({ ownerId }) => ownerId === owner),
      })),
  };

  const spend = (owner: CoinOwner, coins: number) => {
    entries.push({
      id: `spend:${crypto.randomUUID()}`,
      ownerId: owner,
      kind: "refund",
      amount: -coins,
      productId: "spent",
      originalTransactionId: "spent",
      at: 0,
    });
    return Promise.resolve();
  };

  return { repository, notifications: () => [...notifications.values()], spend };
};
