import { Clock, Context, Effect, Layer } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { MetricEventName } from "@billet/contracts-domain/metrics";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { MetricsRepository } from "./metrics-repository.ts";

/** The UTC calendar day of a moment, `YYYY-MM-DD`. */
export const utcDay = (millis: number): string => new Date(millis).toISOString().slice(0, 10);

export interface MetricEvent {
  readonly userId: UserId;
  /** Absent before the person has a partner. */
  readonly pairId?: PairId | undefined;
  readonly name: MetricEventName;
  readonly detail?: string | undefined;
  readonly value?: number | undefined;
  /**
   * The build and system the app said it was (`clientInfoOf`), for what the app reports. Absent for
   * what the server records itself.
   */
  readonly client?: { readonly appVersion: string; readonly os: string } | undefined;
}

/**
 * First-party counts, with no third-party service. `record` never fails and never waits on
 * anything but one write: a broken counter is logged with a fixed label and the request that
 * caused it carries on.
 */
export class Metrics extends Context.Service<
  Metrics,
  {
    readonly record: (event: MetricEvent) => Effect.Effect<void>;
  }
>()("@billet/backend-metrics/Metrics") {
  static readonly layer: Layer.Layer<Metrics, never, MetricsRepository> = Layer.effect(
    Metrics,
    Effect.gen(function* () {
      const repository = yield* MetricsRepository;
      return Metrics.of({
        record: ({ userId, pairId, name, detail, value, client }) =>
          Clock.currentTimeMillis.pipe(
            Effect.flatMap((at) =>
              repository.record({ pairId: pairId ?? "", userId, name, at, detail, value, client }),
            ),
            Effect.catchCause(() => Effect.logWarning("metric not recorded")),
          ),
      });
    }),
  );

  /** Records nothing. For tests and for a Worker without a database. */
  static readonly silent = Layer.succeed(Metrics, { record: () => Effect.void });
}
