import { Layer } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { socketRoute } from "@billet/contracts-realtime/socket-route";
import { AuthRoutes } from "@billet/backend-auth/auth-routes";
import { AuthService } from "@billet/backend-auth/auth-service";
import { Experiments, registry, type Experiment } from "@billet/backend-flags/experiments";
import { FlagsRoutes } from "@billet/backend-flags/flags-routes";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { Metrics } from "@billet/backend-metrics/metrics";
import { MetricsRoutes } from "@billet/backend-metrics/metrics-routes";
import { NotesRoutes } from "@billet/backend-notes/notes-routes";
import { NotesService } from "@billet/backend-notes/notes-service";
import { PairingRoutes } from "@billet/backend-pairing/pairing-routes";
import { PairingService } from "@billet/backend-pairing/pairing-service";
import { FlagsRepositoryLive } from "./flags-repository-live.ts";
import { AppleIdentityLive } from "./apple-identity-live.ts";
import { AuthRepositoryLive } from "./auth-repository-live.ts";
import { MediaStoreLive } from "./media-store-live.ts";
import { MetricsRepositoryLive } from "./metrics-repository-live.ts";
import { PairingObserverLive } from "./pairing-observer-live.ts";
import { PairRoomsLive } from "./pair-rooms-live.ts";
import { PairingRepositoryLive } from "./pairing-repository-live.ts";
import { respondPlaceholder } from "./placeholder-fetch.ts";
import { withRequestLog } from "./observability.ts";
import { limitRequest } from "./rate-limit.ts";
import { respondSocket } from "./socket-fetch.ts";
import type { WorkerEnv } from "./worker-env.ts";

const apiRoutes = (env: WorkerEnv, experiments: ReadonlyArray<Experiment>) =>
  Layer.mergeAll(AuthRoutes, PairingRoutes, NotesRoutes, FlagsRoutes, MetricsRoutes).pipe(
    Layer.provide(
      Layer.mergeAll(
        AuthService.layer,
        // A new pair gets its experiment variants, and the funnel is counted, as part of pairing.
        PairingService.layer.pipe(
          Layer.provide(PairingObserverLive.pipe(Layer.provide(FlagsService.layer))),
        ),
        NotesService.layer,
        FlagsService.layer,
      ),
    ),
    Layer.provide(
      Layer.mergeAll(
        AuthRepositoryLive(env.DB),
        PairingRepositoryLive(env.DB),
        FlagsRepositoryLive(env.DB),
        Metrics.layer.pipe(Layer.provide(MetricsRepositoryLive(env.DB))),
        Experiments.with(experiments),
        MediaStoreLive(env.MEDIA),
        PairRoomsLive(env.PAIR_ROOM),
        AppleIdentityLive,
        Digest.layerWebCrypto,
        SecureRandom.layerWebCrypto,
      ),
    ),
  );

/**
 * The `Api` Worker's `fetch`. The router is built per request, because the services under it hold
 * I/O that a Worker can't share between requests. Anything outside `/v1/` is the placeholder, which
 * the deploy smoke test reads. `experiments` is the registry; only tests pass another list.
 */
export const respondApi = (
  request: Request,
  env: WorkerEnv,
  ctx: ExecutionContext,
  experiments: ReadonlyArray<Experiment> = registry,
): Promise<Response> =>
  new URL(request.url).pathname.startsWith("/v1/")
    ? withRequestLog(request, () => routeApi(request, env, ctx, experiments))
    : Promise.resolve(respondPlaceholder());

const routeApi = async (
  request: Request,
  env: WorkerEnv,
  ctx: ExecutionContext,
  experiments: ReadonlyArray<Experiment>,
): Promise<Response> => {
  if (new URL(request.url).pathname === socketRoute.path) return respondSocket(request, env);

  const limited = await limitRequest(request, env.DB);
  if (limited !== undefined) return limited;

  const { handler, dispose } = HttpRouter.toWebHandler(apiRoutes(env, experiments), {
    disableLogger: true,
  });
  try {
    return await handler(request);
  } finally {
    ctx.waitUntil(dispose());
  }
};
