import { ByteSize, Effect, Layer } from "effect";
import {
  HttpIncomingMessage,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
} from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures } from "@billet/backend-auth/auth-routes";
import { MoodCheckIn } from "@billet/contracts-domain/mood";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { SetMoodRequest } from "@billet/contracts-http-api/mood";
import { routes } from "@billet/contracts-http-api/routes";
import { MoodService } from "./mood-service.ts";

/** A mood is a word and a short note. */
const bodySizeLimit = ByteSize.kibibytes(1);

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondCheckIn = HttpServerResponse.schemaJson(MoodCheckIn);

/** The mood route of the API. Needs `AuthService` and `MoodService`. */
export const MoodRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const moods = yield* MoodService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.setMood.method,
      routes.setMood.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(SetMoodRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit),
        );
        return yield* respondCheckIn(yield* moods.set(userId, request));
      }).pipe(
        Effect.catchTags({
          NotesNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
          InvalidNote: () => respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 }),
          NotesUnavailable: (error) =>
            Effect.logError("mood unavailable", error).pipe(
              Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
            ),
        }),
        respondFailures,
      ),
    );
  }),
).pipe(Layer.orDie);
