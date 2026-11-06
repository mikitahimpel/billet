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
import { GuessAnswerRequest, GuessResponse } from "@billet/contracts-http-api/guess";
import { routes } from "@billet/contracts-http-api/routes";
import { GuessService } from "./guess-service.ts";
import type { GuessRefused, NotesNotFound, NotesUnavailable } from "./notes-error.ts";

/** An answer is a day and two small numbers. */
const bodySizeLimit = ByteSize.kibibytes(1);

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondGuess = HttpServerResponse.schemaJson(GuessResponse);
const headers = { "cache-control": "no-store" };

const respondGuessFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | NotesNotFound | NotesUnavailable | GuessRefused,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      NotesNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      // A locked answer and a closed round are a conflict with what the room holds; a question
      // that is not in the round is a bad request.
      GuessRefused: ({ reason }) =>
        respondError(ApiError.cases.InvalidRequest.make({}), {
          status: reason === "NotInRound" ? 400 : 409,
        }),
      NotesUnavailable: (error) =>
        Effect.logError("who knows who unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/** The Who knows who routes of the API. Needs `AuthService` and `GuessService`. */
export const GuessRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const guess = yield* GuessService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.getGuess.method,
      routes.getGuess.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        return yield* respondGuess(yield* guess.run(userId, { _tag: "View" }), { headers });
      }).pipe(respondGuessFailures),
    );
    yield* router.add(
      routes.answerGuess.method,
      routes.answerGuess.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(GuessAnswerRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit),
        );
        const view = yield* guess.run(userId, { _tag: "Answer", ...request });
        return yield* respondGuess(view, { headers });
      }).pipe(respondGuessFailures),
    );
  }),
).pipe(Layer.orDie);
