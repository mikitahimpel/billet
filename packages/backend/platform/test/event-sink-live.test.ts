import { Effect } from "effect";
import { describe, expect, it } from "vitest";
import { EventSink } from "@billet/backend-metrics/analytics";
import { dataPointOf, EventSinkLive } from "../src/event-sink-live.ts";

const point = {
  name: "AppOpened",
  pairHash: "0123456789abcdef",
  variants: "home-direction=window-seat",
  appVersion: "1.0.0+12",
  os: "iOS 26.1",
} as const;

const write = (dataset: AnalyticsEngineDataset | undefined) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const sink = yield* EventSink;
      yield* sink.write(point);
    }).pipe(Effect.provide(EventSinkLive(dataset))),
  );

describe("EventSinkLive", () => {
  it("keeps the documented column order", () => {
    expect(dataPointOf(point)).toEqual({
      indexes: ["0123456789abcdef"],
      blobs: [
        "AppOpened",
        "0123456789abcdef",
        "home-direction=window-seat",
        "1.0.0+12",
        "iOS 26.1",
      ],
      doubles: [1],
    });
  });

  it("samples events before pairing under one fixed index", () => {
    expect(dataPointOf({ ...point, pairHash: "" }).indexes).toEqual(["unpaired"]);
  });

  it("writes one point per event", async () => {
    const written: Array<AnalyticsEngineDataPoint | undefined> = [];
    await write({ writeDataPoint: (p) => void written.push(p) });
    expect(written).toEqual([dataPointOf(point)]);
  });

  it("never fails the caller, bound or not", async () => {
    await expect(write(undefined)).resolves.toBeUndefined();
    await expect(
      write({
        writeDataPoint: () => {
          throw new Error("down");
        },
      }),
    ).resolves.toBeUndefined();
  });
});
