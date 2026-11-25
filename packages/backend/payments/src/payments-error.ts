import { Data } from "effect";

/** `reason` is a fixed label for the logs, never quoting the input. */
export class InvalidPurchase extends Data.TaggedError("InvalidPurchase")<{
  readonly reason: string;
}> {}

/** The caller has no pair, or a mock refund names a transaction it never bought. */
export class PaymentsNotFound extends Data.TaggedError("PaymentsNotFound") {}

/** A dependency failed, so nothing changed. The client can retry; `reason` is a fixed label. */
export class PaymentsUnavailable extends Data.TaggedError("PaymentsUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}

/** The App Store subscription is bound to another Ourio account, which keeps it. */
export class SubscriptionTaken extends Data.TaggedError("SubscriptionTaken") {}

/** The parcel was opened already, as something else. */
export class ParcelOpened extends Data.TaggedError("ParcelOpened") {}

/** A parcel may not become this: the shop does not sell it, or it costs more than the ceiling. */
export class ParcelRefused extends Data.TaggedError("ParcelRefused")<{ readonly reason: string }> {}

/** The pair owns the piece already; a parcel is for something new. */
export class PieceOwned extends Data.TaggedError("PieceOwned")<{ readonly itemId: string }> {}
