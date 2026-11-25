import { Effect, Option } from "effect";
import type {
  PlusRepository,
  StoredParcel,
  StoredPeriod,
  StoredSubscription,
} from "../src/plus-repository.ts";

/** The test double for `PlusRepository`. Single-threaded, so each method is trivially atomic. */
export const makeInMemoryPlusRepository = (): PlusRepository["Service"] => {
  const subscriptions = new Map<string, StoredSubscription>();
  const periods = new Map<string, StoredPeriod>();
  const parcels = new Map<string, StoredParcel>();

  return {
    recordsOf: (users) =>
      Effect.sync(() => ({
        subscriptions: [...subscriptions.values()].filter(({ userId }) => users.includes(userId)),
        periods: [...periods.values()].filter(({ userId }) => users.includes(userId)),
        parcels: [...parcels.values()].filter(({ payer }) => users.includes(payer)),
      })),
    findSubscription: (id) => Effect.sync(() => Option.fromNullishOr(subscriptions.get(id))),
    saveSubscription: (subscription) =>
      Effect.sync(() => {
        const current = subscriptions.get(subscription.originalTransactionId);
        if (current !== undefined && current.userId !== subscription.userId) return current;
        const saved =
          current === undefined ? subscription : { ...subscription, createdAt: current.createdAt };
        subscriptions.set(subscription.originalTransactionId, saved);
        return saved;
      }),
    savePeriod: (period) =>
      Effect.sync(() => {
        const current = periods.get(period.transactionId);
        periods.set(
          period.transactionId,
          current === undefined ? period : { ...current, revokedAt: period.revokedAt },
        );
      }),
    openParcel: (parcel) =>
      Effect.sync(() => {
        const current = parcels.get(parcel.id);
        if (current !== undefined) return current;
        parcels.set(parcel.id, parcel);
        return parcel;
      }),
    parcelsOfTransaction: (transactionId) =>
      Effect.sync(() =>
        [...parcels.values()].filter((parcel) => parcel.transactionId === transactionId),
      ),
    setParcelStatus: (id, status) =>
      Effect.sync(() => {
        const current = parcels.get(id);
        if (current !== undefined) parcels.set(id, { ...current, status });
      }),
  };
};
