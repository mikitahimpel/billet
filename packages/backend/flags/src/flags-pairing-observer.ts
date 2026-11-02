import { Effect, Layer } from "effect";
import { PairingObserver } from "@billet/backend-pairing/pairing-observer";
import { FlagsService } from "./flags-service.ts";

/**
 * Gives a new pair its experiment variants the moment it exists. If this fails nothing is lost:
 * the first read of the flags works the same assignment out again.
 */
export const FlagsPairingObserver: Layer.Layer<PairingObserver, never, FlagsService> = Layer.effect(
  PairingObserver,
  Effect.gen(function* () {
    const flags = yield* FlagsService;
    return PairingObserver.of({
      invited: () => Effect.void,
      paired: (pairId) => flags.assignPair(pairId).pipe(Effect.ignore),
    });
  }),
);
