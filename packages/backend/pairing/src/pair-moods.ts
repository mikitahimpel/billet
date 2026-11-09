import { Context, Effect, Layer } from "effect";
import type { MoodCheckIn } from "@billet/contracts-domain/mood";
import type { PairId } from "@billet/contracts-domain/pair-id";

/** Never fails: an unreachable room reads as no check-ins, so the pair snapshot still answers. */
export class PairMoods extends Context.Service<
  PairMoods,
  { readonly latest: (pairId: PairId) => Effect.Effect<ReadonlyArray<MoodCheckIn>> }
>()("@billet/backend-pairing/PairMoods") {
  /** No check-ins ever. For tests and for a Worker without rooms. */
  static readonly none = Layer.succeed(PairMoods, { latest: () => Effect.succeed([]) });
}
