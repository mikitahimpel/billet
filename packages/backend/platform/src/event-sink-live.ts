import { Effect, Layer } from "effect";
import { EventSink, type AnalyticsPoint } from "@billet/backend-metrics/analytics";
import { spanMethods } from "@billet/backend-observability/span-methods";

/** Positions are the query schema (docs/experiments.md): never reorder; append new blobs. */
export const dataPointOf = (point: AnalyticsPoint): AnalyticsEngineDataPoint => ({
  // Analytics Engine samples by index, so one pair's events stay together.
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

/** A malformed point is dropped with a fixed log line; without the binding nothing is written. */
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
