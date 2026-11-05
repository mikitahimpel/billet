import { ByteSize, Effect, Layer, type Schema } from "effect";
import {
  HttpIncomingMessage,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
} from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { ApiError } from "@billet/contracts-http-api/api-error";
import {
  DeleteGiftWishRequest,
  GiftsResponse,
  MarkGiftReceivedRequest,
  SaveGiftWishRequest,
  SaveLovesRequest,
  SetGiftPlanRequest,
} from "@billet/contracts-http-api/gifts";
import { routes, type Route } from "@billet/contracts-http-api/routes";
import type { GiftCommand } from "@billet/backend-pair-room/gifts";
import { type GiftNotAllowed, GiftsService } from "./gifts-service.ts";
import type { NotesNotFound, NotesUnavailable } from "./notes-error.ts";

/** The largest request is one wish: a title, a link, a price and a note. */
const bodySizeLimit = ByteSize.kibibytes(16);

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondGifts = HttpServerResponse.schemaJson(GiftsResponse);
// Plans are one person's secret, so no cache may keep an answer.
const headers = { "cache-control": "no-store" };

const respondGiftFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | NotesNotFound | GiftNotAllowed | NotesUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      NotesNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      GiftNotAllowed: () => respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 }),
      NotesUnavailable: (error) =>
        Effect.logError("gifts unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

const limited = Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit);

/** The gift routes of the API. Needs `AuthService` and `GiftsService`. */
export const GiftsRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const gifts = yield* GiftsService;
    const principal = principalOf(yield* AuthService);

    const add = <A>(
      route: Route,
      body: Schema.Codec<A, unknown> | undefined,
      command: (request: A) => GiftCommand,
    ) =>
      router.add(
        route.method,
        route.path,
        Effect.gen(function* () {
          const { userId } = yield* principal;
          const request =
            body === undefined
              ? (undefined as A)
              : yield* HttpServerRequest.schemaBodyJson(body).pipe(limited);
          return yield* respondGifts(yield* gifts.run(userId, command(request)), { headers });
        }).pipe(respondGiftFailures),
      );

    yield* add(routes.getGifts, undefined, () => ({ _tag: "View" }));
    yield* add(routes.saveGiftWish, SaveGiftWishRequest, (wish) => ({ _tag: "SaveWish", wish }));
    yield* add(routes.deleteGiftWish, DeleteGiftWishRequest, ({ id }) => ({
      _tag: "DeleteWish",
      id,
    }));
    yield* add(routes.setGiftPlan, SetGiftPlanRequest, (request) => ({
      _tag: "SetPlan",
      ...request,
    }));
    yield* add(routes.markGiftReceived, MarkGiftReceivedRequest, (request) => ({
      _tag: "MarkReceived",
      ...request,
    }));
    yield* add(routes.saveLoves, SaveLovesRequest, ({ loves }) => ({ _tag: "SaveLoves", loves }));
  }),
).pipe(Layer.orDie);
