import { type Context, Layer } from "effect";
import { Digest, SecureRandom, Signature } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { socketRoute } from "@billet/contracts-realtime/socket-route";
import { AccountDeletion } from "@billet/backend-account/account-deletion";
import { AccountRoutes } from "@billet/backend-account/account-routes";
import { AuthRoutes } from "@billet/backend-auth/auth-routes";
import { AuthService } from "@billet/backend-auth/auth-service";
import { DemoPartnerRoutes } from "@billet/backend-demo-partner/demo-partner-routes";
import { DemoPartnerService } from "@billet/backend-demo-partner/demo-partner-service";
import { Experiments, registry, type Experiment } from "@billet/backend-flags/experiments";
import { FlagsRoutes } from "@billet/backend-flags/flags-routes";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { ServiceStatus } from "@billet/backend-flags/service-status";
import type { AppStatus } from "@billet/contracts-http-api/status";
import { Metrics } from "@billet/backend-metrics/metrics";
import { MetricsRoutes } from "@billet/backend-metrics/metrics-routes";
import { ActivityRoutes } from "@billet/backend-notes/activity-routes";
import { ActivityService } from "@billet/backend-notes/activity-service";
import { CatRoutes } from "@billet/backend-notes/cat-routes";
import { GiftsRoutes } from "@billet/backend-notes/gifts-routes";
import { GiftsService } from "@billet/backend-notes/gifts-service";
import { ReactionRoutes } from "@billet/backend-notes/reaction-routes";
import { ReactionService } from "@billet/backend-notes/reaction-service";
import { CatService } from "@billet/backend-notes/cat-service";
import { NotesRoutes } from "@billet/backend-notes/notes-routes";
import { OnboardingCatalogue } from "@billet/backend-onboarding/catalogue";
import { OnboardingRoutes } from "@billet/backend-onboarding/onboarding-routes";
import { OnboardingService } from "@billet/backend-onboarding/onboarding-service";
import { NotesService } from "@billet/backend-notes/notes-service";
import { PairingRoutes } from "@billet/backend-pairing/pairing-routes";
import { PairingService } from "@billet/backend-pairing/pairing-service";
import { PaymentsConfig, settingsForStage } from "@billet/backend-payments/payments-config";
import { PaymentsRoutes } from "@billet/backend-payments/payments-routes";
import { PaymentsService } from "@billet/backend-payments/payments-service";
import { isAdminPath, respondAdmin } from "./admin-fetch.ts";
import { respondAppLink } from "./app-links.ts";
import { readServedStatus } from "./app-status-live.ts";
import { gateRequest } from "./maintenance-gate.ts";
import { EventSinkLive } from "./event-sink-live.ts";
import { FlagConfigRepositoryLive } from "./flag-config-repository-live.ts";
import { FlagsRepositoryLive } from "./flags-repository-live.ts";
import { PairVariantsLive } from "./pair-variants-live.ts";
import { OnboardingRepositoryLive } from "./onboarding-repository-live.ts";
import { AccountNoticesLive, AccountRepositoryLive } from "./account-repository-live.ts";
import { AppleIdentityLive } from "./apple-identity-live.ts";
import { AppleTokenRevokerLive, signInWithAppleKeyOf } from "./apple-token-revoker-live.ts";
import { AuthRepositoryLive } from "./auth-repository-live.ts";
import { DemoBotsLive } from "./demo-bots-live.ts";
import { DemoPartnerRepositoryLive } from "./demo-partner-repository-live.ts";
import { BetterAuthEngineLive } from "./better-auth-engine.ts";
import { MediaStoreLive } from "./media-store-live.ts";
import { MetricsRepositoryLive } from "./metrics-repository-live.ts";
import { PairingObserverLive } from "./pairing-observer-live.ts";
import { PairRoomsLive } from "./pair-rooms-live.ts";
import { PairingRepositoryLive } from "./pairing-repository-live.ts";
import { PaymentsRepositoryLive } from "./payments-repository-live.ts";
import { PaymentsSwitchLive } from "./payments-switch-live.ts";
import { PairWalletLive } from "./pair-wallet-live.ts";
import { respondPlaceholder } from "./placeholder-fetch.ts";
import { withRequestSpan } from "./observability.ts";
import { limitRequest } from "./rate-limit.ts";
import { respondSocket } from "./socket-fetch.ts";
import type { WorkerEnv } from "./worker-env.ts";
import { type Now, systemNow } from "./wall-clock.ts";

const apiRoutes = (env: WorkerEnv, experiments: ReadonlyArray<Experiment>, status: AppStatus) => {
  // The stage decides which App Store environments count, and whether the dev extras (Xcode
  // transactions, mock purchases, demo-room callers, demo partners) exist at all.
  const settings = settingsForStage(env.STAGE);
  const payments = PaymentsConfig.with(settings);
  // A new pair gets its experiment variants, and the funnel is counted, as part of pairing.
  const pairing = PairingService.layer.pipe(
    Layer.provide(PairingObserverLive.pipe(Layer.provide(FlagsService.layer))),
  );
  return Layer.mergeAll(
    AuthRoutes,
    settings.devTools ? DemoPartnerRoutes : Layer.empty,
    AccountRoutes,
    PairingRoutes,
    NotesRoutes,
    ActivityRoutes,
    CatRoutes,
    ReactionRoutes,
    GiftsRoutes,
    FlagsRoutes,
    MetricsRoutes,
    PaymentsRoutes,
    OnboardingRoutes,
  ).pipe(
    Layer.provide(
      Layer.mergeAll(
        AuthService.layer,
        AccountDeletion.layer,
        pairing,
        DemoPartnerService.layer.pipe(
          Layer.provide(
            Layer.mergeAll(pairing, AccountDeletion.layer, DemoBotsLive(env.PAIR_ROOM)),
          ),
        ),
        NotesService.layer,
        ActivityService.layer,
        CatService.layer,
        ReactionService.layer,
        GiftsService.layer,
        FlagsService.layer,
        PairVariantsLive,
        ServiceStatus.with(status),
        // Bought coins go to the pair's wallet in its room, as well as to the payments ledger.
        PaymentsService.layer.pipe(
          Layer.provide(PairWalletLive.pipe(Layer.provide(NotesService.layer))),
        ),
        // Buying coins is off until the `payments` flag says `on` for the pair, except on dev.
        PaymentsSwitchLive.pipe(Layer.provide(FlagsService.layer)),
        payments,
        OnboardingService.layer,
      ),
    ),
    Layer.provide(
      Layer.mergeAll(
        AuthRepositoryLive(env.DB),
        BetterAuthEngineLive(env.DB),
        AccountRepositoryLive(env.DB),
        AccountNoticesLive(env.DB),
        DemoPartnerRepositoryLive(env.DB),
        AppleTokenRevokerLive(signInWithAppleKeyOf(env)),
        PairingRepositoryLive(env.DB),
        PaymentsRepositoryLive(env.DB),
        payments,
        FlagsRepositoryLive(env.DB),
        FlagConfigRepositoryLive(env.DB, caches.default),
        OnboardingRepositoryLive(env.DB),
        OnboardingCatalogue.seed,
        Metrics.layer.pipe(Layer.provide(MetricsRepositoryLive(env.DB))),
        Experiments.with(experiments),
        EventSinkLive(env.EVENTS),
        MediaStoreLive(env.MEDIA),
        PairRoomsLive(env.PAIR_ROOM),
        AppleIdentityLive,
        Digest.layerWebCrypto,
        SecureRandom.layerWebCrypto,
        Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto)),
      ),
    ),
  );
};

/**
 * The `Api` Worker's `fetch`. The router is built per request, because the services under it hold
 * I/O that a Worker can't share between requests. `/admin` is the admin panel, behind Cloudflare
 * Access (admin-fetch.ts). Universal Links for invites are app-links.ts. Anything else outside
 * `/v1/` is the placeholder, which the deploy smoke test reads. `experiments` is the registry and `now` the wall clock; only tests pass others.
 */
export const respondApi = (
  request: Request,
  env: WorkerEnv,
  ctx: ExecutionContext,
  experiments: ReadonlyArray<Experiment> = registry,
  now: Now = systemNow,
): Promise<Response> => {
  const { pathname } = new URL(request.url);
  if (pathname.startsWith("/v1/")) {
    return withRequestSpan(request, (context) =>
      routeApi(request, env, ctx, experiments, context, now),
    );
  }
  if (isAdminPath(pathname)) {
    return withRequestSpan(request, (context) =>
      respondAdmin(request, env, ctx, { experiments, context }),
    );
  }
  const appLink = respondAppLink(pathname);
  if (appLink === undefined) return Promise.resolve(respondPlaceholder());
  return limitRequest(request, env.DB, now()).then((limited) =>
    limited === undefined
      ? appLink
      : new Response("Too many tries. Open the link again in a minute.", {
          status: 429,
          headers: {
            "content-type": "text/plain; charset=utf-8",
            "cache-control": "no-store",
            "retry-after": limited.headers.get("retry-after") ?? "60",
          },
        }),
  );
};

const routeApi = async (
  request: Request,
  env: WorkerEnv,
  ctx: ExecutionContext,
  experiments: ReadonlyArray<Experiment>,
  context: Context.Context<never>,
  now: Now,
): Promise<Response> => {
  // The service status comes first, from KV: `/v1/status` and the maintenance 503 must answer
  // while D1 or the rest of the API is down, so nothing before this may touch the database.
  const status = await readServedStatus(env.STATUS);
  const gated = gateRequest(request, status, now());
  if (gated !== undefined) return gated;

  if (new URL(request.url).pathname === socketRoute.path)
    return respondSocket(request, env, context);

  const limited = await limitRequest(request, env.DB, now());
  if (limited !== undefined) return limited;

  const { handler, dispose } = HttpRouter.toWebHandler(apiRoutes(env, experiments, status), {
    disableLogger: true,
  });
  try {
    return await handler(request, context);
  } finally {
    ctx.waitUntil(dispose());
  }
};
