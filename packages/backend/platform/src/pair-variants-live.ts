import { Effect, Layer } from "effect";
import { FlagsRepository } from "@billet/backend-flags/flags-repository";
import { PairVariants } from "@billet/backend-metrics/analytics";

/** `PairVariants` from the stored assignments. A storage failure labels the events with none. */
export const PairVariantsLive: Layer.Layer<PairVariants, never, FlagsRepository> = Layer.effect(
  PairVariants,
  Effect.gen(function* () {
    const flags = yield* FlagsRepository;
    return PairVariants.of({
      of: (pairId) =>
        flags.find(pairId).pipe(
          Effect.map((rows) =>
            rows.map(({ experimentKey, variant }) => ({ key: experimentKey, variant })),
          ),
          Effect.catch(() => Effect.succeed([])),
        ),
    });
  }),
);
