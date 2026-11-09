import { ByteSize, Effect, Layer } from "effect";
import {
  HttpIncomingMessage,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
} from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures } from "@billet/backend-auth/auth-routes";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { routes } from "@billet/contracts-http-api/routes";
import {
  RecordStreakDayRequest,
  RestoreStreakRequest,
  StreakResponse,
} from "@billet/contracts-http-api/streak";
import type { NotesUnavailable } from "./notes-error.ts";
import { StreakService } from "./streak-service.ts";

/** A day or a restore is a time and an offset. */
const bodySizeLimit = ByteSize.kibibytes(1);

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondStreak = HttpServerResponse.schemaJson(StreakResponse);

const notFound = () => respondError(ApiError.cases.NotFound.make({}), { status: 404 });

const unavailable = (error: NotesUnavailable) =>
  Effect.logError("streak unavailable", error).pipe(
    Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
  );

/** The streak routes of the API. Needs `AuthService` and `StreakService`. */
export const StreakRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const streaks = yield* StreakService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.getStreak.method,
      routes.getStreak.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        return yield* respondStreak({ streak: yield* streaks.get(userId) });
      }).pipe(
        Effect.catchTags({ NotesNotFound: notFound, NotesUnavailable: unavailable }),
        respondFailures,
      ),
    );

    yield* router.add(
      routes.recordStreakDay.method,
      routes.recordStreakDay.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(RecordStreakDayRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit),
        );
        return yield* respondStreak({ streak: yield* streaks.recordDay(userId, request) });
      }).pipe(
        Effect.catchTags({ NotesNotFound: notFound, NotesUnavailable: unavailable }),
        respondFailures,
      ),
    );

    yield* router.add(
      routes.restoreStreak.method,
      routes.restoreStreak.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(RestoreStreakRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit),
        );
        return yield* respondStreak({ streak: yield* streaks.restore(userId, request) });
      }).pipe(
        Effect.catchTags({
          NotesNotFound: notFound,
          StreakNotRestorable: () =>
            respondError(ApiError.cases.StreakNotRestorable.make({}), { status: 409 }),
          NotesUnavailable: unavailable,
        }),
        respondFailures,
      ),
    );
  }),
).pipe(Layer.orDie);
