import { Schema } from "effect";

const nonEmpty = Schema.String.check(Schema.isNonEmpty());
const stampCount = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** `POST /v1/purchases`: StoreKit 2's `Transaction.jwsRepresentation`, as the app received it. */
export const PurchaseRequest = Schema.Struct({ signedTransaction: nonEmpty });
export type PurchaseRequest = typeof PurchaseRequest.Type;

/**
 * `POST /v1/purchases/mock`, served on the dev stage only. Credits (`purchase`) or takes back
 * (`refund`) a pack without the App Store, under a transaction id the client makes up.
 */
export const MockPurchaseRequest = Schema.Struct({
  productId: nonEmpty,
  transactionId: Schema.String.check(Schema.isPattern(/^mock-[A-Za-z0-9-]{1,64}$/)),
  kind: Schema.Literals(["purchase", "refund"]),
});
export type MockPurchaseRequest = typeof MockPurchaseRequest.Type;

/**
 * What a purchase did. `stamps` is what this transaction credited, or for a mock refund what it
 * took back, as a positive number. `duplicate` is true when the transaction had already been
 * handled: nothing changed, and `balance` is the current one.
 */
export const PurchaseResponse = Schema.Struct({
  transactionId: nonEmpty,
  productId: nonEmpty,
  stamps: stampCount,
  balance: stampCount,
  duplicate: Schema.Boolean,
});
export type PurchaseResponse = typeof PurchaseResponse.Type;

/**
 * One change to a ledger. `id` is stable (`purchase:<originalTransactionId>`,
 * `refund:<originalTransactionId>`), so a client can merge entries it already holds. `amount` is
 * negative for a refund. `at` is ISO 8601 in UTC.
 */
export const StampEntry = Schema.Struct({
  id: nonEmpty,
  kind: Schema.Literals(["purchase", "refund"]),
  amount: Schema.Int,
  productId: nonEmpty,
  at: nonEmpty,
});
export type StampEntry = typeof StampEntry.Type;

/** `GET /v1/stamps`: the bought stamps of the caller's pair. `balance` is never below 0. */
export const StampsResponse = Schema.Struct({
  balance: stampCount,
  entries: Schema.Array(StampEntry),
});
export type StampsResponse = typeof StampsResponse.Type;

/** `POST /v1/appstore/notifications`: an App Store Server Notification V2, as Apple sends it. */
export const AppStoreNotificationRequest = Schema.Struct({ signedPayload: nonEmpty });
export type AppStoreNotificationRequest = typeof AppStoreNotificationRequest.Type;
