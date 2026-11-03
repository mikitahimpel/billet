import { Context, type Effect, Schema } from "effect";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { MetricEventName } from "@billet/contracts-domain/metrics";
import type { MetricsUnavailable } from "./metrics-error.ts";

/**
 * What a `pair_events` row holds: how many times one person did one named thing on one UTC day.
 * There is nothing else in it: no note, image, text, device, address or place. `pairId` is empty
 * for what happens before pairing. A test in `platform` fails if the table's columns differ.
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
});
export type StoredMetric = typeof StoredMetric.Type;

/**
 * An `event_details` row: how many times one name came with one detail on one UTC day, and the sum
 * of their values. No user and no pair.
 */
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
}

/** Counts. Failure is a defect for the caller to log: a counter must never fail a request. */
export class MetricsRepository extends Context.Service<
  MetricsRepository,
  {
    /**
     * Adds one to the day's count, or starts it, and the same for its detail when it has one. Two
     * at once both count.
     */
    readonly record: (occurrence: MetricOccurrence) => Effect.Effect<void, MetricsUnavailable>;
    /** Every row, oldest day first, for tests. */
    readonly all: Effect.Effect<ReadonlyArray<StoredMetric>, MetricsUnavailable>;
    /** Every detail row, oldest day first, for tests. */
    readonly details: Effect.Effect<ReadonlyArray<StoredDetail>, MetricsUnavailable>;
  }
>()("@billet/backend-metrics/MetricsRepository") {}
