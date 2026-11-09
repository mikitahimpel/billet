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
  /** `clientInfoOf`, for what the app reports; absent for what the server records. */
  readonly client?: { readonly appVersion: string; readonly os: string } | undefined;
}

/**
 * `record` never fails: a broken counter is logged with a fixed label and the request carries on.
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
