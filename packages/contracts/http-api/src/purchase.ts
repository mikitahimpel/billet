import { Schema } from "effect";

const nonEmpty = Schema.String.check(Schema.isNonEmpty());
const coinCount = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

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
 * What a purchase did. `coins` is what this transaction credited, or for a mock refund what it
 * took back, as a positive number. `balance` is the pair's wallet after it (`GET /v1/coins`: coins
 * earned, bought and spent), or a demo room's bought coins. `duplicate` is true when the
 * transaction had already been handled: nothing changed, and `balance` is the current one.
 */
export const PurchaseResponse = Schema.Struct({
  transactionId: nonEmpty,
  productId: nonEmpty,
  coins: coinCount,
  balance: coinCount,
  duplicate: Schema.Boolean,
});
export type PurchaseResponse = typeof PurchaseResponse.Type;

/**
 * One change to a ledger. `id` is stable (`purchase:<originalTransactionId>`,
 * `refund:<originalTransactionId>`), so a client can merge entries it already holds. `amount` is
 * negative for a refund. `at` is ISO 8601 in UTC.
 */
export const PurchaseEntry = Schema.Struct({
  id: nonEmpty,
  kind: Schema.Literals(["purchase", "refund"]),
  amount: Schema.Int,
  productId: nonEmpty,
  at: nonEmpty,
});
export type PurchaseEntry = typeof PurchaseEntry.Type;

/** `GET /v1/purchases`: the bought coins of the caller's pair. `balance` is never below 0. */
export const PurchasesResponse = Schema.Struct({
  balance: coinCount,
  entries: Schema.Array(PurchaseEntry),
});
export type PurchasesResponse = typeof PurchasesResponse.Type;

/** `POST /v1/appstore/notifications`: an App Store Server Notification V2, as Apple sends it. */
export const AppStoreNotificationRequest = Schema.Struct({ signedPayload: nonEmpty });
export type AppStoreNotificationRequest = typeof AppStoreNotificationRequest.Type;
