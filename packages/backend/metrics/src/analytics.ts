import { Context, Effect, Layer } from "effect";
import { Digest } from "effect/crypto";
import type { MetricEventName } from "@billet/contracts-domain/metrics";
import type { PairId } from "@billet/contracts-domain/pair-id";

/**
 * One accepted event as it goes to Workers Analytics Engine. This is the whole of it: no user id,
 * no Apple subject, no email, no address, no place and nothing a note says or shows. The pair is a
 * one-way hash (see `pairHashOf`). The layout of the stored row is in docs/experiments.md.
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
  /** A price in stamps (`ClientEvent.value`). Absent when none. */
  readonly value?: number | undefined;
}

const encoder = new TextEncoder();

/**
 * The pair id as Analytics Engine sees it: the first 16 hex digits of SHA-256 over a fixed prefix
 * and the id. Pair ids are random, so the hash cannot be turned back into one; the admin, who has
 * the id, can compute it to find a pair's rows.
 */
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

/**
 * Where accepted events are written besides the D1 counts. Writing never fails and never blocks the
 * response: Analytics Engine takes a point without waiting, and a broken one is dropped.
 */
export class EventSink extends Context.Service<
  EventSink,
  { readonly write: (point: AnalyticsPoint) => Effect.Effect<void> }
>()("@billet/backend-metrics/EventSink") {
  /** Writes nothing. For tests and for a Worker without the dataset bound. */
  static readonly silent = Layer.succeed(EventSink, { write: () => Effect.void });
}

/**
 * The variants a pair has been given, for labelling its events. Provided by the platform from the
 * flags table, so this package does not depend on the flags one. A failure means no label.
 */
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
