import { ByteSize, Effect, Layer } from "effect";
import {
  HttpIncomingMessage,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
} from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { PickSwipeRequest, PickTonightResponse } from "@billet/contracts-http-api/pick-tonight";
import { routes } from "@billet/contracts-http-api/routes";
import { PickTonightService } from "./pick-tonight-service.ts";
import type { NotesNotFound, NotesUnavailable } from "./notes-error.ts";

/** A swipe is a card, a choice and the card's name. */
const bodySizeLimit = ByteSize.kibibytes(4);

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondPick = HttpServerResponse.schemaJson(PickTonightResponse);
const headers = { "cache-control": "no-store" };

const respondPickFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | NotesNotFound | NotesUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      NotesNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      NotesUnavailable: (error) =>
        Effect.logError("pick tonight unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/** The Pick tonight routes of the API. Needs `AuthService` and `PickTonightService`. */
export const PickTonightRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const pick = yield* PickTonightService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.getPickTonight.method,
      routes.getPickTonight.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        return yield* respondPick(yield* pick.run(userId, { _tag: "View" }), { headers });
      }).pipe(respondPickFailures),
    );
    yield* router.add(
      routes.swipePickTonight.method,
      routes.swipePickTonight.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(PickSwipeRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit),
        );
        const view = yield* pick.run(userId, { _tag: "Swipe", ...request });
        return yield* respondPick(view, { headers });
      }).pipe(respondPickFailures),
    );
  }),
).pipe(Layer.orDie);
