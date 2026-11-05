import { Effect, Layer } from "effect";
import { HttpRouter, HttpServerResponse } from "effect/http";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { AuthService } from "@billet/backend-auth/auth-service";
import type { AlreadyPaired } from "@billet/backend-pairing/pairing-error";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { DemoPartnerResponse, PairResponse } from "@billet/contracts-http-api/pair";
import { routes } from "@billet/contracts-http-api/routes";
import type { DemoPartnerUnavailable, NoDemoPartner } from "./demo-partner-error.ts";
import { DemoPartnerService } from "./demo-partner-service.ts";

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondPair = HttpServerResponse.schemaJson(PairResponse);
const respondDemo = HttpServerResponse.schemaJson(DemoPartnerResponse);

const respondDemoFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | AlreadyPaired | NoDemoPartner | DemoPartnerUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      AlreadyPaired: () => respondError(ApiError.cases.AlreadyPaired.make({}), { status: 409 }),
      NoDemoPartner: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      DemoPartnerUnavailable: (error) =>
        Effect.logError("demo partner unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/**
 * The demo partner routes. Needs `AuthService` and `DemoPartnerService`. Only the dev stage mounts
 * them: anywhere else a bot is a user no one can delete.
 */
export const DemoPartnerRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const demo = yield* DemoPartnerService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.createDemoPartner.method,
      routes.createDemoPartner.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const pair = yield* demo.create(userId);
        return yield* respondPair(pair, { headers: { "cache-control": "no-store" } });
      }).pipe(respondDemoFailures),
    );

    yield* router.add(
      routes.getDemoPartner.method,
      routes.getDemoPartner.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const status = yield* demo.status(userId);
        return yield* respondDemo(status, { headers: { "cache-control": "no-store" } });
      }).pipe(respondDemoFailures),
    );

    yield* router.add(
      routes.removeDemoPartner.method,
      routes.removeDemoPartner.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        yield* demo.remove(userId);
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondDemoFailures),
    );
  }),
).pipe(Layer.orDie);
