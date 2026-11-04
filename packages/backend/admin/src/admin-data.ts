import { Context, Data, type Effect } from "effect";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { EventRow, FlagRow } from "@billet/backend-metrics/funnel";
import type { DetailRow } from "./admin-top-details.ts";

/** A read failed. The panel answers 503; `reason` is a fixed label. */
export class AdminUnavailable extends Data.TaggedError("AdminUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}

/** A stamp-pack purchase, as the panel lists it. `ownerId` is a pair id or `demo:<code>`. */
export interface PurchaseRow {
  readonly originalTransactionId: string;
  readonly transactionId: string;
  readonly ownerId: string;
  readonly productId: string;
  readonly stamps: number;
  readonly environment: string;
  readonly status: string;
  readonly refunds: number;
  /** A refund took back less than the pack, because the owner had fewer stamps left. */
  readonly flagged: boolean;
  readonly purchasedAt: number;
  readonly createdAt: number;
  readonly updatedAt: number;
}

/** One stamp ledger entry. */
export interface StampEntryRow {
  readonly id: string;
  readonly ownerId: string;
  readonly kind: string;
  readonly amount: number;
  readonly productId: string;
  readonly at: number;
}

/** One App Store Server Notification, and what was done with it. */
export interface NotificationRow {
  readonly notificationUuid: string;
  readonly type: string;
  readonly subtype: string | null;
  readonly environment: string | null;
  readonly originalTransactionId: string | null;
  readonly outcome: string;
  readonly receivedAt: number;
}

/**
 * What the panel reads from the directory, besides the flags services. Read-only. It never reads a
 * note, an image, an Apple subject or a push token: counts, pair ids, purchases and dates only.
 */
export class AdminData extends Context.Service<
  AdminData,
  {
    /** Every `pair_events` row. The same rows the owner report reads. */
    readonly events: Effect.Effect<ReadonlyArray<EventRow>, AdminUnavailable>;
    /** Every `event_details` row: which cats, items and toys were chosen, apart from anyone. */
    readonly details: Effect.Effect<ReadonlyArray<DetailRow>, AdminUnavailable>;
    /** Every `pair_flags` row. */
    readonly assignments: Effect.Effect<ReadonlyArray<FlagRow>, AdminUnavailable>;
    readonly userCount: Effect.Effect<number, AdminUnavailable>;
    /** The newest `limit` purchases, ledger entries and App Store notifications, newest first. */
    readonly purchases: (limit: number) => Effect.Effect<
      {
        readonly purchases: ReadonlyArray<PurchaseRow>;
        readonly ledger: ReadonlyArray<StampEntryRow>;
        readonly notifications: ReadonlyArray<NotificationRow>;
      },
      AdminUnavailable
    >;
    /** How many accounts are in the pair now, and when the first joined it. */
    readonly pair: (
      pairId: PairId,
    ) => Effect.Effect<
      { readonly members: number; readonly pairedAt: number | null },
      AdminUnavailable
    >;
  }
>()("@billet/backend-admin/AdminData") {}
