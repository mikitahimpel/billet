import { Context, type Effect, Schema } from "effect";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { MetricEventName } from "@billet/contracts-domain/metrics";
import type { MetricsUnavailable } from "./metrics-error.ts";

/**
 * No note, image, text, device or place; `pairId` is empty before pairing. Checked in `platform`.
 */
export const StoredMetric = Schema.Struct({
  pairId: Schema.String,
  userId: UserId,
  name: MetricEventName,
  /** UTC calendar day, `YYYY-MM-DD`. */
  day: Schema.String.check(Schema.isPattern(/^\d{4}-\d{2}-\d{2}$/)),
  count: Schema.Int,
  firstAt: EpochMillis,
  lastAt: EpochMillis,
  /** The build the app said it was on the day's latest report, or null (server-recorded names). */
  appVersion: Schema.NullOr(Schema.String),
  /** The system, the same way. */
  os: Schema.NullOr(Schema.String),
});
export type StoredMetric = typeof StoredMetric.Type;

/** Per UTC day, name and detail: a count and the sum of values. No user and no pair. */
export const StoredDetail = Schema.Struct({
  name: MetricEventName,
  detail: Schema.String,
  day: Schema.String.check(Schema.isPattern(/^\d{4}-\d{2}-\d{2}$/)),
  count: Schema.Int,
  total: Schema.Int,
});
export type StoredDetail = typeof StoredDetail.Type;

/** One occurrence, before it is added to its day's count. */
export interface MetricOccurrence {
  readonly pairId: string;
  readonly userId: UserId;
  readonly name: MetricEventName;
  readonly at: EpochMillis;
  /** Also counted in `event_details`, apart from the person, when present. */
  readonly detail?: string | undefined;
  /** Added to the detail's `total`. Only with a detail. */
  readonly value?: number | undefined;
  /** The build and system the app reported with it. Kept as the day's latest; absent keeps it. */
  readonly client?: { readonly appVersion: string; readonly os: string } | undefined;
}

/** Counts. Failure is a defect for the caller to log: a counter must never fail a request. */
export class MetricsRepository extends Context.Service<
  MetricsRepository,
  {
    /** Adds one to the day's count (and its detail's); concurrent calls both count. */
    readonly record: (occurrence: MetricOccurrence) => Effect.Effect<void, MetricsUnavailable>;
    /** Every row, oldest day first, for tests. */
    readonly all: Effect.Effect<ReadonlyArray<StoredMetric>, MetricsUnavailable>;
    /** Every detail row, oldest day first, for tests. */
    readonly details: Effect.Effect<ReadonlyArray<StoredDetail>, MetricsUnavailable>;
  }
>()("@billet/backend-metrics/MetricsRepository") {}
