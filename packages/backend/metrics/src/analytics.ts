import { Context, Effect, Layer } from "effect";
import { Digest } from "effect/crypto";
import type { MetricEventName } from "@billet/contracts-domain/metrics";
import type { PairId } from "@billet/contracts-domain/pair-id";

/**
 * Nothing else is stored: no user id, Apple subject, email, place or note. See docs/experiments.md.
 */
export interface AnalyticsPoint {
  readonly name: MetricEventName;
  /** `pairHashOf` the pair, or empty before pairing. */
  readonly pairHash: string;
  /** The pair's stored variants, `key=variant` joined by commas in key order. Empty when none. */
  readonly variants: string;
  readonly appVersion: string;
  readonly os: string;
  /** The event's catalogue id or closed-list word (`ClientEvent.detail`). Empty when none. */
  readonly detail?: string | undefined;
  /** A price in coins (`ClientEvent.value`). Absent when none. */
  readonly value?: number | undefined;
}

const encoder = new TextEncoder();

/** First 16 hex digits of SHA-256 over a fixed prefix and the id; the admin can compute it. */
export const pairHashOf = (pairId: PairId): Effect.Effect<string, never, Digest.Digest> =>
  Effect.gen(function* () {
    const digest = yield* Digest.Digest;
    const hex = yield* digest
      .digestHex(Digest.sha256, encoder.encode(`billet-pair:${pairId}`))
      .pipe(Effect.orDie);
    return hex.slice(0, 16);
  });

/** The stored variants in the one order every row uses. */
export const variantsLabel = (
  assignments: ReadonlyArray<{ readonly key: string; readonly variant: string }>,
): string =>
  assignments
    .map(({ key, variant }) => `${key}=${variant}`)
    .toSorted()
    .join(",");

/** Writing never fails and never blocks the response; a broken point is dropped. */
export class EventSink extends Context.Service<
  EventSink,
  { readonly write: (point: AnalyticsPoint) => Effect.Effect<void> }
>()("@billet/backend-metrics/EventSink") {
  /** Writes nothing. For tests and for a Worker without the dataset bound. */
  static readonly silent = Layer.succeed(EventSink, { write: () => Effect.void });
}

/** Provided by the platform from the flags table, so this package doesn't depend on flags. */
export class PairVariants extends Context.Service<
  PairVariants,
  {
    readonly of: (
      pairId: PairId,
    ) => Effect.Effect<ReadonlyArray<{ readonly key: string; readonly variant: string }>>;
  }
>()("@billet/backend-metrics/PairVariants") {
  static readonly none = Layer.succeed(PairVariants, { of: () => Effect.succeed([]) });
}
