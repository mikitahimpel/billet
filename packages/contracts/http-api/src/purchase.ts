import { Schema } from "effect";

const nonEmpty = Schema.String.check(Schema.isNonEmpty());
const coinCount = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** `POST /v1/purchases`: StoreKit 2's `Transaction.jwsRepresentation`, as the app received it. */
export const PurchaseRequest = Schema.Struct({ signedTransaction: nonEmpty });
export type PurchaseRequest = typeof PurchaseRequest.Type;

/** Dev stage only: credits or refunds a pack without the App Store, under a made-up id. */
export const MockPurchaseRequest = Schema.Struct({
  productId: nonEmpty,
  transactionId: Schema.String.check(Schema.isPattern(/^mock-[A-Za-z0-9-]{1,64}$/)),
  kind: Schema.Literals(["purchase", "refund"]),
});
export type MockPurchaseRequest = typeof MockPurchaseRequest.Type;

/**
 * `coins` is positive, refunds too; `balance` is the wallet after. `duplicate`: nothing changed.
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
 * `id` is stable: `<kind>:<originalTransactionId>`. Refunds have `amount` < 0. `at` ISO 8601 UTC.
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
