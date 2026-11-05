import { Context, Effect, Layer } from "effect";
import type { MoodCheckIn } from "@billet/contracts-domain/mood";
import type { PairId } from "@billet/contracts-domain/pair-id";

/**
 * Each member's latest check-in, which the pair's room holds, for the pair snapshot. It never
 * fails: a room it cannot reach reads as no check-ins, so the snapshot still answers.
 */
export class PairMoods extends Context.Service<
  PairMoods,
  { readonly latest: (pairId: PairId) => Effect.Effect<ReadonlyArray<MoodCheckIn>> }
>()("@billet/backend-pairing/PairMoods") {
  /** No check-ins ever. For tests and for a Worker without rooms. */
  static readonly none = Layer.succeed(PairMoods, { latest: () => Effect.succeed([]) });
}
