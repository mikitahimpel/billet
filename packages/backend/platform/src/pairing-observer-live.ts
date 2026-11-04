import { Effect, Layer } from "effect";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { Metrics } from "@billet/backend-metrics/metrics";
import { PairingObserver } from "@billet/backend-pairing/pairing-observer";
import { spanMethods } from "@billet/backend-observability/span-methods";

/**
 * What the Worker does when pairing succeeds: gives the new pair its experiment variants (if that
 * fails, the first read of the flags does it) and counts the funnel steps. Both are best effort.
 */
export const PairingObserverLive: Layer.Layer<PairingObserver, never, FlagsService | Metrics> =
  Layer.effect(
    PairingObserver,
    Effect.gen(function* () {
      const flags = yield* FlagsService;
      const metrics = yield* Metrics;
      return PairingObserver.of(
        spanMethods("PairingObserver", {
          invited: (userId) => metrics.record({ userId, name: "InviteCreated" }),
          paired: (pairId, members) =>
            Effect.all(
              [
                flags.assignPair(pairId).pipe(Effect.ignore),
                ...members.map((userId) => metrics.record({ userId, pairId, name: "PairClaimed" })),
              ],
              { discard: true },
            ),
        }),
      );
    }),
  );
