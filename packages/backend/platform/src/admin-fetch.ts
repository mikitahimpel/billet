import { Context, Effect, Layer } from "effect";
import { Digest, SecureRandom, Signature } from "effect/crypto";
import { FetchHttpClient, HttpRouter } from "effect/http";
import { Jwks } from "effect/jose";
import {
  accessCertsUrl,
  accessConfigOf,
  accessJwtHeader,
  AccessVerifier,
  accessVerifierLayer,
  denyAll,
  type AccessIdentity,
  type AdminIdentity,
} from "@billet/backend-admin/access";
import { adminCss, adminHtml, adminJs, adminLibJs } from "@billet/backend-admin/admin-assets";
import {
  AdminRoutes,
  agentApiPrefix,
  AgentRoutes,
  CurrentAdmin,
  PanelEnvironment,
} from "@billet/backend-admin/admin-routes";
import { Experiments, type Experiment } from "@billet/backend-flags/experiments";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { AdminDataLive } from "./admin-data-live.ts";
import { Observability } from "./observability.ts";
import { AppStatusStoreLive } from "./app-status-live.ts";
import { FlagConfigRepositoryLive } from "./flag-config-repository-live.ts";
import { FlagsRepositoryLive } from "./flags-repository-live.ts";
import { PairingRepositoryLive } from "./pairing-repository-live.ts";
import type { WorkerEnv } from "./worker-env.ts";

/** Whether a path belongs to the admin panel. Everything under it is behind the Access check. */
export const isAdminPath = (pathname: string) =>
  pathname === "/admin" || pathname.startsWith("/admin/");

const contentSecurityPolicy = [
  "default-src 'none'",
  "script-src 'self'",
  "style-src 'self'",
  "connect-src 'self'",
  "img-src 'self' data:",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ");

const securityHeaders = {
  "content-security-policy": contentSecurityPolicy,
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "cross-origin-opener-policy": "same-origin",
  "cross-origin-resource-policy": "same-origin",
  "cache-control": "no-store",
  "x-robots-tag": "noindex",
};

const withSecurity = (response: Response): Response => {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(securityHeaders)) headers.set(name, value);
  return new Response(response.body, { status: response.status, headers });
};

const forbidden = () =>
  withSecurity(
    new Response("Forbidden", { status: 403, headers: { "content-type": "text/plain" } }),
  );

// The team's keys, fetched like Apple's (see apple-identity-live.ts): no redirects, and only a
// successful answer is cached by Cloudflare, for 10 minutes.
const remoteKeys = (url: string): Layer.Layer<Jwks.Jwks> =>
  Jwks.layerRemote({ url }).pipe(
    Layer.orDie,
    Layer.provide(
      FetchHttpClient.layer.pipe(
        Layer.provide(
          Layer.succeed(FetchHttpClient.RequestInit, {
            redirect: "manual",
            cf: { cacheEverything: true, cacheTtlByStatus: { "200-299": 600, "300-599": 0 } },
          }),
        ),
      ),
    ),
  );

const signature = Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto));

/** Options for tests: the experiments, and the Access keys in place of the team's. */
export interface AdminOptions {
  readonly experiments: ReadonlyArray<Experiment>;
  readonly accessKeys?: Layer.Layer<Jwks.Jwks>;
  /** The request span's context (observability.ts), so the panel's spans and logs join it. */
  readonly context?: Context.Context<never>;
}

/** Fails closed: no configuration, no header, or any doubt about the token is `undefined`. */
export const verifyAccess = async (
  request: Request,
  env: WorkerEnv,
  accessKeys?: Layer.Layer<Jwks.Jwks>,
  context: Context.Context<never> = Context.empty(),
): Promise<AccessIdentity | undefined> => {
  const config = accessConfigOf(env.ACCESS_TEAM_DOMAIN, env.ACCESS_AUD, env.ACCESS_AGENT_AUD);
  const verifier =
    config === undefined
      ? denyAll
      : accessVerifierLayer(config).pipe(
          Layer.provide(
            Layer.mergeAll(accessKeys ?? remoteKeys(accessCertsUrl(config)), signature),
          ),
        );
  const token = request.headers.get(accessJwtHeader);
  return Effect.runPromiseWith(context)(
    Effect.gen(function* () {
      const access = yield* AccessVerifier;
      return yield* access.verify(token);
    }).pipe(
      Effect.provide(verifier),
      Effect.tapError(({ reason }) => Effect.logWarning("admin access denied", reason)),
      Effect.orElseSucceed(() => undefined),
      Effect.catchCause((cause) =>
        Effect.logError("admin access check failed", cause).pipe(Effect.as(undefined)),
      ),
      Effect.provide(Observability),
    ),
  );
};

/**
 * A browser sends `Origin` on every cross-site write; a write from another site must not ride the
 * Access cookie. Same-origin writes from the page carry the panel's own origin.
 */
const isSameOriginWrite = (request: Request) => {
  if (request.method === "GET" || request.method === "HEAD") return true;
  const origin = request.headers.get("origin");
  const site = request.headers.get("sec-fetch-site");
  return origin === new URL(request.url).origin && (site === null || site === "same-origin");
};

const asset = (body: string, type: string) =>
  withSecurity(new Response(body, { headers: { "content-type": `${type}; charset=utf-8` } }));

const dataLayer = (env: WorkerEnv, experiments: ReadonlyArray<Experiment>) =>
  Layer.mergeAll(
    PairingRepositoryLive(env.DB),
    FlagsRepositoryLive(env.DB),
    FlagConfigRepositoryLive(env.DB, caches.default),
    AdminDataLive(env.DB),
    Experiments.with(experiments),
    AppStatusStoreLive(env.STATUS),
    Digest.layerWebCrypto,
  );

const adminLayer = (env: WorkerEnv, experiments: ReadonlyArray<Experiment>, admin: AdminIdentity) =>
  AdminRoutes.pipe(
    Layer.provide(
      Layer.mergeAll(
        FlagsService.layer,
        Layer.succeed(CurrentAdmin, admin),
        Layer.succeed(PanelEnvironment, { name: env.STAGE || "unknown" }),
      ).pipe(Layer.provideMerge(dataLayer(env, experiments))),
    ),
  );

const agentLayer = (env: WorkerEnv, experiments: ReadonlyArray<Experiment>) =>
  AgentRoutes.pipe(
    Layer.provide(FlagsService.layer.pipe(Layer.provideMerge(dataLayer(env, experiments)))),
  );

const route = async (
  layer: Layer.Layer<never, never, HttpRouter.HttpRouter>,
  request: Request,
  ctx: ExecutionContext,
  context: Context.Context<never>,
) => {
  const { handler, dispose } = HttpRouter.toWebHandler(layer, { disableLogger: true });
  try {
    return withSecurity(await handler(request, context));
  } finally {
    ctx.waitUntil(dispose());
  }
};

/**
 * Everything under `/admin`: the page, its script and style, and the JSON API. The Access check
 * runs first, before any routing, and a request that fails it gets the same bare 403 whatever the
 * path, so nothing about the panel is visible without a valid Access token.
 *
 * A service token (an agent) may only GET `/admin/api/agent/...`; anything else it sends, every
 * write included, is the same 403. Each agent read is logged with the token's `common_name`.
 */
export const respondAdmin = async (
  request: Request,
  env: WorkerEnv,
  ctx: ExecutionContext,
  options: AdminOptions,
): Promise<Response> => {
  const context = options.context ?? Context.empty();
  const identity = await verifyAccess(request, env, options.accessKeys, context);
  if (identity === undefined) return forbidden();
  const { pathname } = new URL(request.url);

  if (identity.kind === "agent") {
    if (request.method !== "GET" || !pathname.startsWith(agentApiPrefix)) return forbidden();
    await Effect.runPromiseWith(context)(
      Effect.logInfo("admin agent read").pipe(
        Effect.annotateLogs({ commonName: identity.commonName, pathname }),
        Effect.provide(Observability),
      ),
    );
    return route(agentLayer(env, options.experiments), request, ctx, context);
  }

  if (!isSameOriginWrite(request)) return forbidden();
  if (request.method === "GET") {
    if (pathname === "/admin" || pathname === "/admin/") return asset(adminHtml, "text/html");
    if (pathname === "/admin/app.css") return asset(adminCss, "text/css");
    if (pathname === "/admin/app.js") return asset(adminJs, "text/javascript");
    if (pathname === "/admin/lib.js") return asset(adminLibJs, "text/javascript");
  }
  if (!pathname.startsWith("/admin/api/")) {
    return withSecurity(new Response("Not found", { status: 404 }));
  }
  return route(
    adminLayer(env, options.experiments, { email: identity.email }),
    request,
    ctx,
    context,
  );
};
