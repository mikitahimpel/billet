import { Effect, Layer } from "effect";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { AuthService } from "@billet/backend-auth/auth-service";
import type { AlreadyPaired, InvalidInvite } from "@billet/backend-pairing/pairing-error";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { ClaimInviteResponse, ClaimReviewCodeRequest } from "@billet/contracts-http-api/invite";
import { routes } from "@billet/contracts-http-api/routes";
import type { ReviewUnavailable } from "./review-error.ts";
import { ReviewService } from "./review-service.ts";

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondClaim = HttpServerResponse.schemaJson(ClaimInviteResponse);

const respondReviewFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | InvalidInvite | AlreadyPaired | ReviewUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      InvalidInvite: () => respondError(ApiError.cases.InvalidInvite.make({}), { status: 404 }),
      AlreadyPaired: () => respondError(ApiError.cases.AlreadyPaired.make({}), { status: 409 }),
      ReviewUnavailable: (error) =>
        Effect.logError("review unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/** Answered as an invite claim is, so the app treats both alike. The code is never logged. */
export const ReviewRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const review = yield* ReviewService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.claimReviewCode.method,
      routes.claimReviewCode.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { code } = yield* HttpServerRequest.schemaBodyJson(ClaimReviewCodeRequest);
        const pairId = yield* review.claim(userId, code);
        return yield* respondClaim({ pairId }, { headers: { "cache-control": "no-store" } });
      }).pipe(respondReviewFailures),
    );
  }),
).pipe(Layer.orDie);
