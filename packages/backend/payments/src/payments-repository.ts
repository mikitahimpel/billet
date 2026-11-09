import { Context, type Effect, type Option, Schema } from "effect";
import { EpochMillis } from "@billet/contracts-domain/ids";
import type { PaymentsUnavailable } from "./payments-error.ts";

/** A pair id, or `demo:<code>` for a demo room on the dev stage. Both partners share the pair's
 * coins, and a new pair starts from none. */
export const CoinOwner = Schema.String.check(Schema.isNonEmpty()).pipe(Schema.brand("CoinOwner"));
export type CoinOwner = typeof CoinOwner.Type;

export const PurchaseStatus = Schema.Literals(["credited", "refunded"]);
export type PurchaseStatus = typeof PurchaseStatus.Type;

/** What each stored table holds. A test in `platform` fails if a table's columns differ. */
export const StoredPurchase = Schema.Struct({
  /** The App Store's `originalTransactionId`, or a mock transaction id. Credited once. */
  originalTransactionId: Schema.String,
  transactionId: Schema.String,
  ownerId: CoinOwner,
  productId: Schema.String,
  coins: Schema.Int,
  /** `Production`, `Sandbox`, `Xcode` or `Mock`. */
  environment: Schema.String,
  status: PurchaseStatus,
  /** How many times it has been refunded; the next ledger entry ids count on it. */
  refunds: Schema.Int,
  /** 1 when a refund took back fewer coins than the pack, because the pair had fewer left. */
  flagged: Schema.Int,
  purchasedAt: EpochMillis,
  createdAt: EpochMillis,
  updatedAt: EpochMillis,
});
export type StoredPurchase = typeof StoredPurchase.Type;

export const PurchaseEntryKind = Schema.Literals(["purchase", "refund"]);

/** One change to an owner's coins. The balance is the sum of `amount`, never below 0. */
export const StoredPurchaseEntry = Schema.Struct({
  id: Schema.String,
  ownerId: CoinOwner,
  kind: PurchaseEntryKind,
  amount: Schema.Int,
  productId: Schema.String,
  originalTransactionId: Schema.String,
  at: EpochMillis,
});
export type StoredPurchaseEntry = typeof StoredPurchaseEntry.Type;

/** Every App Store Server Notification handled, so each is applied once. */
export const StoredNotification = Schema.Struct({
  notificationUuid: Schema.String,
  type: Schema.String,
  subtype: Schema.NullOr(Schema.String),
  environment: Schema.NullOr(Schema.String),
  originalTransactionId: Schema.NullOr(Schema.String),
  /** What was done: `refunded`, `restored`, `duplicate`, `unknown-transaction`, `recorded`… */
  outcome: Schema.String,
  receivedAt: EpochMillis,
});
export type StoredNotification = typeof StoredNotification.Type;

export interface NewPurchase {
  readonly originalTransactionId: string;
  readonly transactionId: string;
  readonly ownerId: CoinOwner;
  readonly productId: string;
  readonly coins: number;
  readonly environment: string;
  readonly purchasedAt: number;
  readonly at: number;
}

export interface Balance {
  readonly balance: number;
}

export interface Credited extends Balance {
  /** The purchase was already stored (for this owner or another), so nothing was credited. */
  readonly duplicate: boolean;
}

export interface Reversal extends Balance {
  /** Nothing changed: the purchase was not in the state the reversal starts from. */
  readonly duplicate: boolean;
  /** The coins this step took back (a refund) or gave back (a restore), as a positive number. */
  readonly coins: number;
}

export interface Ledger extends Balance {
  readonly entries: ReadonlyArray<StoredPurchaseEntry>;
}

/** Each method is one atomic operation; every storage failure is `PaymentsUnavailable`.
 * `test/payments-repository-contract.ts` is the behaviour any implementation must pass. */
export class PaymentsRepository extends Context.Service<
  PaymentsRepository,
  {
    /** Credits once per `originalTransactionId`; a purchase already stored, for any owner,
     * credits nothing. */
    readonly credit: (purchase: NewPurchase) => Effect.Effect<Credited, PaymentsUnavailable>;
    readonly findPurchase: (
      originalTransactionId: string,
    ) => Effect.Effect<Option.Option<StoredPurchase>, PaymentsUnavailable>;
    /** Takes back at most the owner's balance, flagging the purchase when short; records
     * `notification` in the same batch. A purchase not `credited` with `refunds` as given is left
     * alone (`duplicate`). */
    readonly refund: (
      purchase: StoredPurchase,
      at: number,
      notification?: StoredNotification,
    ) => Effect.Effect<Reversal, PaymentsUnavailable>;
    /** Gives back what the last refund took (Apple reversed it) as a `purchase` entry, and marks
     * it credited again. */
    readonly restore: (
      purchase: StoredPurchase,
      at: number,
      notification?: StoredNotification,
    ) => Effect.Effect<Reversal, PaymentsUnavailable>;
    readonly hasNotification: (uuid: string) => Effect.Effect<boolean, PaymentsUnavailable>;
    /** Stores a notification once; a second one with the same UUID changes nothing. */
    readonly recordNotification: (
      notification: StoredNotification,
    ) => Effect.Effect<void, PaymentsUnavailable>;
    /** The owner's balance and entries, oldest first. */
    readonly ledger: (owner: CoinOwner) => Effect.Effect<Ledger, PaymentsUnavailable>;
  }
>()("@billet/backend-payments/PaymentsRepository") {}

/** The ledger entry id of a purchase, and of its `n`th refund or restore (from 1). */
export const entryIds = {
  purchase: (id: string) => `purchase:${id}`,
  refund: (id: string, n: number) => (n === 1 ? `refund:${id}` : `refund:${id}:${n}`),
  restore: (id: string, n: number) => (n === 1 ? `restore:${id}` : `restore:${id}:${n}`),
};
