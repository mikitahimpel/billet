import { Effect, Layer } from "effect";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { ApiError } from "@billet/contracts-http-api/api-error";
import {
  OnboardingResponse,
  SaveOnboardingAnswerRequest,
} from "@billet/contracts-http-api/onboarding";
import { routes } from "@billet/contracts-http-api/routes";
import type { InvalidAnswer, OnboardingUnavailable } from "./onboarding-error.ts";
import { OnboardingService } from "./onboarding-service.ts";

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondCatalogue = HttpServerResponse.schemaJson(OnboardingResponse);

const respondOnboardingFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | InvalidAnswer | OnboardingUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      InvalidAnswer: ({ reason }) =>
        Effect.logInfo("onboarding answer refused", reason).pipe(
          Effect.andThen(respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 })),
        ),
      OnboardingUnavailable: (error) =>
        Effect.logError("onboarding unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/**
 * The onboarding routes of the API. Any session will do, the anonymous one from first launch
 * included. Needs `AuthService` and `OnboardingService`.
 */
export const OnboardingRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const onboarding = yield* OnboardingService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.getOnboarding.method,
      routes.getOnboarding.path,
      Effect.gen(function* () {
        yield* principal;
        // Never cached: a changed question has to reach the next launch.
        return yield* respondCatalogue(onboarding.catalogue, {
          headers: { "cache-control": "no-store" },
        });
      }).pipe(respondOnboardingFailures),
    );

    yield* router.add(
      routes.saveOnboardingAnswer.method,
      routes.saveOnboardingAnswer.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(SaveOnboardingAnswerRequest);
        yield* onboarding.save(userId, request);
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondOnboardingFailures),
    );
  }),
).pipe(Layer.orDie);
