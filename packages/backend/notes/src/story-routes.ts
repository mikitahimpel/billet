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
import { StoryMarkRequest, StoryResponse } from "@billet/contracts-http-api/story";
import { routes } from "@billet/contracts-http-api/routes";
import { StoryService } from "./story-service.ts";
import type { InvalidStory, NotesNotFound, NotesUnavailable } from "./notes-error.ts";

/** A mark is three short ids. */
const bodySizeLimit = ByteSize.kibibytes(4);

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondStory = HttpServerResponse.schemaJson(StoryResponse);
const headers = { "cache-control": "no-store" };

const respondStoryFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | NotesNotFound | InvalidStory | NotesUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      InvalidStory: () => respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 }),
      NotesNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      NotesUnavailable: (error) =>
        Effect.logError("story unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/** The story routes of the API. Needs `AuthService` and `StoryService`. */
export const StoryRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const story = yield* StoryService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.getStory.method,
      routes.getStory.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        return yield* respondStory(yield* story.run(userId, { _tag: "View" }), { headers });
      }).pipe(respondStoryFailures),
    );
    yield* router.add(
      routes.markStory.method,
      routes.markStory.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(StoryMarkRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit),
        );
        const view = yield* story.run(userId, { _tag: "Mark", ...request });
        return yield* respondStory(view, { headers });
      }).pipe(respondStoryFailures),
    );
  }),
).pipe(Layer.orDie);
