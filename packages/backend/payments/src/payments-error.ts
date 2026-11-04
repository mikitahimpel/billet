import { Data } from "effect";

/**
 * An App Store transaction or notification that is refused: its signature, chain, bundle,
 * environment or product. `reason` is a fixed label for the logs, never quoting the input.
 */
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
