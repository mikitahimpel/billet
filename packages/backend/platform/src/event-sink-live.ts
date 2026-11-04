import { Effect, Layer } from "effect";
import { EventSink, type AnalyticsPoint } from "@billet/backend-metrics/analytics";
import { spanMethods } from "@billet/backend-observability/span-methods";

/**
 * The row an `AnalyticsPoint` becomes. Positions are the query schema, so never reorder them:
 * add a new blob at the end. docs/experiments.md lists them.
 */
export const dataPointOf = (point: AnalyticsPoint): AnalyticsEngineDataPoint => ({
  // The sampling key: Analytics Engine samples by index, so one pair's events stay together.
  indexes: [point.pairHash === "" ? "unpaired" : point.pairHash],
  blobs: [
    point.name,
    point.pairHash,
    point.variants,
    point.appVersion,
    point.os,
    point.detail ?? "",
  ],
  doubles: [1, point.value ?? 0],
});

/**
 * `EventSink` on a Workers Analytics Engine dataset. `writeDataPoint` queues the point and returns
 * at once; it throws only on a malformed point, which is dropped with a fixed log line. Without
 * the binding (tests, a Worker that has none) nothing is written.
 */
export const EventSinkLive = (
  dataset: AnalyticsEngineDataset | undefined,
): Layer.Layer<EventSink> =>
  dataset === undefined
    ? EventSink.silent
    : Layer.succeed(
        EventSink,
        spanMethods("EventSink", {
          write: (point) =>
            Effect.try(() => dataset.writeDataPoint(dataPointOf(point))).pipe(
              Effect.catch(() => Effect.logWarning("analytics point not written")),
            ),
        }),
      );
