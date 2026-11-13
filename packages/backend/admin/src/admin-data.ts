import { Context, Data, type Effect } from "effect";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { FlagRow } from "@billet/backend-metrics/funnel";
import type { BuildEventRow } from "./admin-retention.ts";
import type { OnboardingCountRow } from "@billet/backend-onboarding/onboarding-stats";
import type { DetailRow } from "./admin-top-details.ts";
import type { EconomyDayRow, EconomyPairDayRow } from "./admin-economy.ts";

/** A read failed. The panel answers 503; `reason` is a fixed label. */
export class AdminUnavailable extends Data.TaggedError("AdminUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}

/** A coin-pack purchase, as the panel lists it. `ownerId` is a pair id or `demo:<code>`. */
export interface PurchaseRow {
  readonly originalTransactionId: string;
  readonly transactionId: string;
  readonly ownerId: string;
  readonly productId: string;
  readonly coins: number;
  readonly environment: string;
  readonly status: string;
  readonly refunds: number;
  /** A refund left the pair's wallet below 0: it had spent some of the pack's coins. */
  readonly flagged: boolean;
  readonly purchasedAt: number;
  readonly createdAt: number;
  readonly updatedAt: number;
}

export interface PurchaseEntryRow {
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

export interface ReportRow {
  readonly id: string;
  readonly reporterId: string;
  readonly reportedId: string;
  readonly pairId: string;
  readonly reason: string;
  /** What the reporter typed, if anything: the one place the panel shows a person's words. */
  readonly details: string | null;
  /** The note or photo reported, if the report is about one. */
  readonly noteId: string | null;
  readonly createdAt: number;
}

/**
 * Read-only. Never reads a note, image, Apple subject, push token or typed onboarding answer.
 */
export class AdminData extends Context.Service<
  AdminData,
  {
    /** Every `pair_events` row, with the build and system it carries. The owner report's rows. */
    readonly events: Effect.Effect<ReadonlyArray<BuildEventRow>, AdminUnavailable>;
    /** Every `event_details` row: which cats, items and toys were chosen, apart from anyone. */
    readonly details: Effect.Effect<ReadonlyArray<DetailRow>, AdminUnavailable>;
    readonly assignments: Effect.Effect<ReadonlyArray<FlagRow>, AdminUnavailable>;
    readonly userCount: Effect.Effect<number, AdminUnavailable>;
    /** The newest `limit` purchases, ledger entries and App Store notifications, newest first. */
    readonly purchases: (limit: number) => Effect.Effect<
      {
        readonly purchases: ReadonlyArray<PurchaseRow>;
        readonly ledger: ReadonlyArray<PurchaseEntryRow>;
        readonly notifications: ReadonlyArray<NotificationRow>;
      },
      AdminUnavailable
    >;
    /** The economy's rows from UTC day `since` on: coins by day and source, and each pair's day. */
    readonly economy: (since: string) => Effect.Effect<
      {
        readonly days: ReadonlyArray<EconomyDayRow>;
        readonly pairDays: ReadonlyArray<EconomyPairDayRow>;
      },
      AdminUnavailable
    >;
    /** Every `onboarding_answers` row without its typed text, and how many accounts have one. */
    readonly onboarding: Effect.Effect<
      { readonly rows: ReadonlyArray<OnboardingCountRow>; readonly accounts: number },
      AdminUnavailable
    >;
    /** The newest `limit` partner reports, newest first, and how many there are in all. */
    readonly reports: (
      limit: number,
    ) => Effect.Effect<
      { readonly reports: ReadonlyArray<ReportRow>; readonly total: number },
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
