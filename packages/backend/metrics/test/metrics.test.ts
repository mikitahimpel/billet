import { Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { Metrics, utcDay } from "../src/metrics.ts";
import { MetricsRepository } from "../src/metrics-repository.ts";
import { MetricsUnavailable } from "../src/metrics-error.ts";
import { makeInMemoryMetricsRepository } from "./in-memory-metrics-repository.ts";

const ana = Schema.decodeSync(UserId)("user-a");
const pair = Schema.decodeSync(PairId)("pair-1");

describe("utcDay", () => {
  it("cuts the day at UTC midnight", () => {
    expect(utcDay(Date.UTC(2026, 10, 2, 23, 59, 59, 999))).toBe("2026-11-02");
    expect(utcDay(Date.UTC(2026, 10, 3, 0, 0, 0, 0))).toBe("2026-11-03");
  });
});

describe("Metrics", () => {
  it("records the person, the pair, the name and the clock's time, and nothing else", async () => {
    const { repository, rows } = makeInMemoryMetricsRepository();
    await Effect.runPromise(
      Effect.gen(function* () {
        yield* TestClock.adjust(Date.UTC(2026, 10, 2, 9));
        const metrics = yield* Metrics;
        yield* metrics.record({ userId: ana, pairId: pair, name: "NoteSent" });
      }).pipe(
        Effect.provide(
          Metrics.layer.pipe(Layer.provide(Layer.succeed(MetricsRepository, repository))),
        ),
        Effect.provide(TestClock.layer()),
      ),
    );
    expect([...rows.values()]).toEqual([
      {
        pairId: "pair-1",
        userId: "user-a",
        name: "NoteSent",
        day: "2026-11-02",
        count: 1,
        firstAt: Date.UTC(2026, 10, 2, 9),
        lastAt: Date.UTC(2026, 10, 2, 9),
      },
    ]);
  });

  it("records an empty pair before pairing", async () => {
    const { repository, rows } = makeInMemoryMetricsRepository();
    await Effect.runPromise(
      Effect.gen(function* () {
        yield* (yield* Metrics).record({ userId: ana, name: "InviteCreated" });
      }).pipe(
        Effect.provide(
          Metrics.layer.pipe(Layer.provide(Layer.succeed(MetricsRepository, repository))),
        ),
      ),
    );
    expect([...rows.values()][0]?.pairId).toBe("");
  });

  it("never fails the caller, whether storage fails or dies", async () => {
    const failing = Layer.succeed(MetricsRepository, {
      record: () => Effect.fail(new MetricsUnavailable({ reason: "directory-unavailable" })),
      all: Effect.succeed([]),
    });
    const dying = Layer.succeed(MetricsRepository, {
      record: () => Effect.die("storage is on fire: user-a pair-1"),
      all: Effect.succeed([]),
    });
    for (const repository of [failing, dying]) {
      await expect(
        Effect.runPromise(
          Effect.gen(function* () {
            yield* (yield* Metrics).record({ userId: ana, pairId: pair, name: "NoteSent" });
            return "carried on";
          }).pipe(Effect.provide(Metrics.layer.pipe(Layer.provide(repository)))),
        ),
      ).resolves.toBe("carried on");
    }
  });
});
