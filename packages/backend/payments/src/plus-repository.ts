import { Context, type Effect, type Option, Schema } from "effect";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import type { PaymentsUnavailable } from "./payments-error.ts";

/**
 * One App Store subscription, by its `originalTransactionId`, bound to the account that paid.
 * Plus follows that person, not the pair, so it goes with them through an unpairing.
 */
export const StoredSubscription = Schema.Struct({
  originalTransactionId: Schema.String,
  userId: UserId,
  /** The plan Apple bills now; a change of plan takes effect at the next renewal. */
  productId: Schema.String,
  /** `Production`, `Sandbox`, `Xcode` or `Mock`. */
  environment: Schema.String,
  /** When the paid period ends. Apple keeps it through a billing grace period. */
  expiresAt: EpochMillis,
  autoRenew: Schema.Boolean,
  /** While Apple retries a failed renewal and Plus carries on. */
  graceUntil: Schema.NullOr(EpochMillis),
  /** Apple revoked the whole subscription (`REVOKE`). */
  revokedAt: Schema.NullOr(EpochMillis),
  createdAt: EpochMillis,
  updatedAt: EpochMillis,
});
export type StoredSubscription = typeof StoredSubscription.Type;

/** One paid period: the first purchase or a renewal, each its own `transactionId`. Its parcels
 * are derived from it (`plus-rules.ts`), so nothing schedules them. */
export const StoredPeriod = Schema.Struct({
  transactionId: Schema.String,
  originalTransactionId: Schema.String,
  userId: UserId,
  productId: Schema.String,
  purchasedAt: EpochMillis,
  expiresAt: EpochMillis,
  /** Refunded: its parcels not opened are gone, its opened ones are owed in coins. */
  revokedAt: Schema.NullOr(EpochMillis),
});
export type StoredPeriod = typeof StoredPeriod.Type;

export const ParcelStatus = Schema.Literals(["opened", "refunded"]);

/** A parcel once opened. Parcels waiting are not stored; they are what the periods bring. */
export const StoredParcel = Schema.Struct({
  id: Schema.String,
  /** Who paid for it, so a refund of their period finds it. */
  payer: UserId,
  transactionId: Schema.String,
  /** The pair it was opened in, which got the piece. */
  pairId: PairId,
  /** The `ParcelOffer` chosen, as JSON. */
  offer: Schema.String,
  /** The piece's coin price when it was opened, which a refund of its month takes back. */
  price: Schema.Int,
  openedBy: UserId,
  openedAt: EpochMillis,
  status: ParcelStatus,
});
export type StoredParcel = typeof StoredParcel.Type;

export interface PlusRecords {
  readonly subscriptions: ReadonlyArray<StoredSubscription>;
  readonly periods: ReadonlyArray<StoredPeriod>;
  readonly parcels: ReadonlyArray<StoredParcel>;
}

/** Each method is one atomic operation; every storage failure is `PaymentsUnavailable`.
 * `test/plus-repository-contract.ts` is the behaviour any implementation must pass. */
export class PlusRepository extends Context.Service<
  PlusRepository,
  {
    /** Everything stored for these accounts. */
    readonly recordsOf: (
      users: ReadonlyArray<UserId>,
    ) => Effect.Effect<PlusRecords, PaymentsUnavailable>;
    readonly findSubscription: (
      originalTransactionId: string,
    ) => Effect.Effect<Option.Option<StoredSubscription>, PaymentsUnavailable>;
    /** Stores the subscription for its first account, and changes it only for that account.
     * Answers the row as stored. */
    readonly saveSubscription: (
      subscription: StoredSubscription,
    ) => Effect.Effect<StoredSubscription, PaymentsUnavailable>;
    /** Stores a period once; a period stored already keeps its row but `revokedAt`. */
    readonly savePeriod: (period: StoredPeriod) => Effect.Effect<void, PaymentsUnavailable>;
    /** Stores the open once per parcel id; answers the stored one, which may be another's. */
    readonly openParcel: (parcel: StoredParcel) => Effect.Effect<StoredParcel, PaymentsUnavailable>;
    readonly parcelsOfTransaction: (
      transactionId: string,
    ) => Effect.Effect<ReadonlyArray<StoredParcel>, PaymentsUnavailable>;
    readonly setParcelStatus: (
      id: string,
      status: typeof ParcelStatus.Type,
    ) => Effect.Effect<void, PaymentsUnavailable>;
  }
>()("@billet/backend-payments/PlusRepository") {}
