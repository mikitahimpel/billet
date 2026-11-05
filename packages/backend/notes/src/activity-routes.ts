import { ByteSize, Effect, Layer, Schema } from "effect";
import {
  HttpIncomingMessage,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
} from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { ActivityCursor } from "@billet/contracts-domain/activity";
import {
  ActivityResponse,
  ActivityUnreadResponse,
  MarkActivityReadRequest,
} from "@billet/contracts-http-api/activity";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { routes } from "@billet/contracts-http-api/routes";
import { ActivityService } from "./activity-service.ts";
import type { NotesNotFound, NotesUnavailable } from "./notes-error.ts";

export const activityPageLimit = 50;

const ActivityQuery = Schema.Struct({
  before: Schema.optionalKey(ActivityCursor),
  limit: Schema.optionalKey(
    Schema.NumberFromString.check(
      Schema.isInt(),
      Schema.isBetween({ minimum: 1, maximum: activityPageLimit }),
    ),
  ),
});

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondPage = HttpServerResponse.schemaJson(ActivityResponse);
const respondUnread = HttpServerResponse.schemaJson(ActivityUnreadResponse);

const respondActivityFailures = <R>(
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
        Effect.logError("activity unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/** The Inbox routes of the API. Needs `AuthService` and `ActivityService`. */
export const ActivityRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const activity = yield* ActivityService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.listActivity.method,
      routes.listActivity.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { before, limit = activityPageLimit } =
          yield* HttpServerRequest.schemaSearchParams(ActivityQuery);
        return yield* respondPage(yield* activity.list(userId, before, limit));
      }).pipe(respondActivityFailures),
    );

    yield* router.add(
      routes.markActivityRead.method,
      routes.markActivityRead.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { upTo } = yield* HttpServerRequest.schemaBodyJson(MarkActivityReadRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, ByteSize.kibibytes(1)),
        );
        return yield* respondUnread({ unread: yield* activity.markRead(userId, upTo) });
      }).pipe(respondActivityFailures),
    );
  }),
).pipe(Layer.orDie);
