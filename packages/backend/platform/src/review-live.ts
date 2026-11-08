import { Layer } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { Experiments, type Experiment } from "@billet/backend-flags/experiments";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { Metrics } from "@billet/backend-metrics/metrics";
import { MoodService } from "@billet/backend-notes/mood-service";
import { PairingService } from "@billet/backend-pairing/pairing-service";
import { ReviewService } from "@billet/backend-review/review-service";
import { DemoBotsLive } from "./demo-bots-live.ts";
import { DemoPartnerRepositoryLive } from "./demo-partner-repository-live.ts";
import { FlagConfigRepositoryLive } from "./flag-config-repository-live.ts";
import { FlagsRepositoryLive } from "./flags-repository-live.ts";
import { MediaStoreLive } from "./media-store-live.ts";
import { MetricsRepositoryLive } from "./metrics-repository-live.ts";
import { PairMoodsLive } from "./pair-moods-live.ts";
import { PairRoomsLive } from "./pair-rooms-live.ts";
import { PairingObserverLive } from "./pairing-observer-live.ts";
import { PairingRepositoryLive } from "./pairing-repository-live.ts";
import { ReviewRepositoryLive } from "./review-repository-live.ts";
import type { WorkerEnv } from "./worker-env.ts";

/**
 * `ReviewService` on the Worker's bindings, for the admin panel, which has none of the API's
 * services. Pairing runs with its real observer, so a wipe deletes the pair's room and pictures.
 */
export const ReviewServiceLive = (
  env: WorkerEnv,
  experiments: ReadonlyArray<Experiment>,
): Layer.Layer<ReviewService> => {
  const directory = Layer.mergeAll(
    PairingRepositoryLive(env.DB),
    FlagsRepositoryLive(env.DB),
    FlagConfigRepositoryLive(env.DB, caches.default),
    DemoPartnerRepositoryLive(env.DB),
    ReviewRepositoryLive(env.DB),
    Metrics.layer.pipe(Layer.provide(MetricsRepositoryLive(env.DB))),
    Experiments.with(experiments),
    PairRoomsLive(env.PAIR_ROOM),
    MediaStoreLive(env.MEDIA),
    Digest.layerWebCrypto,
    SecureRandom.layerWebCrypto,
  );
  const pairing = PairingService.layer.pipe(
    Layer.provide(PairingObserverLive.pipe(Layer.provide(FlagsService.layer))),
    Layer.provide(PairMoodsLive.pipe(Layer.provide(MoodService.layer))),
  );
  return ReviewService.layer.pipe(
    Layer.provide(Layer.mergeAll(pairing, DemoBotsLive(env.PAIR_ROOM))),
    Layer.provide(directory),
  );
};
