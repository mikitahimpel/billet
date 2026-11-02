import { Effect, Layer } from "effect";
import { HttpRouter, HttpServerResponse } from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { FlagsResponse } from "@billet/contracts-http-api/flags";
import { routes } from "@billet/contracts-http-api/routes";
import type { FlagsUnavailable } from "./flags-error.ts";
import { FlagsService } from "./flags-service.ts";

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondFlags = HttpServerResponse.schemaJson(FlagsResponse);

const respondFlagsFailures = <R>(
  effect: Effect.Effect<HttpServerResponse.HttpServerResponse, RouteFailure | FlagsUnavailable, R>,
) =>
  effect.pipe(
    Effect.catchTags({
      FlagsUnavailable: ({ reason }) =>
        Effect.logError("flags unavailable", reason).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/** The flags route of the API. Needs `AuthService` and `FlagsService`. */
export const FlagsRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const flags = yield* FlagsService;
    const principal = principalOf(yield* AuthService);

    // Never cached: a switched-off experiment has to reach the next launch.
    yield* router.add(
      routes.getFlags.method,
      routes.getFlags.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        return yield* respondFlags(yield* flags.flagsFor(userId), {
          headers: { "cache-control": "no-store" },
        });
      }).pipe(respondFlagsFailures),
    );
  }),
).pipe(Layer.orDie);
