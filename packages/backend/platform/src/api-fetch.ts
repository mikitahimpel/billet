import { Layer } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { AuthRoutes } from "@billet/backend-auth/auth-routes";
import { AuthService } from "@billet/backend-auth/auth-service";
import { PairingRoutes } from "@billet/backend-pairing/pairing-routes";
import { PairingService } from "@billet/backend-pairing/pairing-service";
import { AppleIdentityLive } from "./apple-identity-live.ts";
import { AuthRepositoryLive } from "./auth-repository-live.ts";
import { PairingRepositoryLive } from "./pairing-repository-live.ts";
import { respondPlaceholder } from "./placeholder-fetch.ts";
import type { WorkerEnv } from "./worker-env.ts";

const apiRoutes = (db: D1Database) =>
  Layer.mergeAll(AuthRoutes, PairingRoutes).pipe(
    Layer.provide(Layer.mergeAll(AuthService.layer, PairingService.layer)),
    Layer.provide(
      Layer.mergeAll(
        AuthRepositoryLive(db),
        PairingRepositoryLive(db),
        AppleIdentityLive,
        Digest.layerWebCrypto,
        SecureRandom.layerWebCrypto,
      ),
    ),
  );

/**
 * The `Api` Worker's `fetch`. The router is built per request, because the services under it hold
 * I/O that a Worker can't share between requests. Anything outside `/v1/` is the placeholder, which
 * the deploy smoke test reads.
 */
export const respondApi = async (
  request: Request,
  env: WorkerEnv,
  ctx: ExecutionContext,
): Promise<Response> => {
  if (!new URL(request.url).pathname.startsWith("/v1/")) return respondPlaceholder();

  const { handler, dispose } = HttpRouter.toWebHandler(apiRoutes(env.DB), { disableLogger: true });
  try {
    return await handler(request);
  } finally {
    ctx.waitUntil(dispose());
  }
};
