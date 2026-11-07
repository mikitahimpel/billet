import { ByteSize, Effect, Layer, Schema } from "effect";
import {
  HttpIncomingMessage,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
} from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { Riddle, RiddleId } from "@billet/contracts-domain/riddle";
import { ApiError } from "@billet/contracts-http-api/api-error";
import {
  GuessRiddleRequest,
  GuessRiddleResponse,
  RiddlesResponse,
  SendRiddleRequest,
} from "@billet/contracts-http-api/riddle";
import { routes } from "@billet/contracts-http-api/routes";
import type { RiddleCommand } from "@billet/backend-pair-room/riddle";
import type { InvalidNote, NotesNotFound, NotesUnavailable, RiddleRefused } from "./notes-error.ts";
import { type RiddleAnswer, RiddleService } from "./riddle-service.ts";

/** A riddle's compact strokes are bounded like a drawing note's; a try is a few words. */
const sendSizeLimit = ByteSize.kibibytes(16);
const guessSizeLimit = ByteSize.kibibytes(1);

const RiddleParams = Schema.Struct({ id: RiddleId });

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondRiddles = HttpServerResponse.schemaJson(RiddlesResponse);
const respondRiddle = HttpServerResponse.schemaJson(Riddle);
const respondGuess = HttpServerResponse.schemaJson(GuessRiddleResponse);
const headers = { "cache-control": "no-store" };

const respondRiddleFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | NotesNotFound | NotesUnavailable | RiddleRefused | InvalidNote,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      NotesNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      InvalidNote: () => respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 }),
      // A word that is no riddle word is a bad request; a missing riddle is not found; the rest
      // conflict with what the room holds.
      RiddleRefused: ({ reason }) =>
        reason === "NotFound"
          ? respondError(ApiError.cases.NotFound.make({}), { status: 404 })
          : respondError(ApiError.cases.InvalidRequest.make({}), {
              status: reason === "BadWord" ? 400 : 409,
            }),
      NotesUnavailable: (error) =>
        Effect.logError("draw-guess unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

const changedOf = (answer: RiddleAnswer) =>
  answer._tag === "Changed"
    ? Effect.succeed(answer)
    : Effect.die("a riddle command answered with the list");

/** The draw-guess routes of the API. Needs `AuthService` and `RiddleService`. */
export const RiddleRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const riddles = yield* RiddleService;
    const principal = principalOf(yield* AuthService);

    const oneRiddle = (command: (id: RiddleId) => RiddleCommand) =>
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { id } = yield* HttpRouter.schemaPathParams(RiddleParams);
        const { riddle } = yield* changedOf(yield* riddles.run(userId, command(id)));
        return yield* respondRiddle(riddle, { headers });
      }).pipe(respondRiddleFailures);

    yield* router.add(
      routes.getRiddles.method,
      routes.getRiddles.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const answer = yield* riddles.run(userId, { _tag: "View" });
        if (answer._tag !== "Listed") return yield* Effect.die("a view answered with a riddle");
        return yield* respondRiddles(answer.view, { headers });
      }).pipe(respondRiddleFailures),
    );
    yield* router.add(
      routes.sendRiddle.method,
      routes.sendRiddle.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(SendRiddleRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, sendSizeLimit),
        );
        const command: RiddleCommand = { _tag: "Send", ...request };
        const { riddle } = yield* changedOf(yield* riddles.run(userId, command));
        return yield* respondRiddle(riddle, { headers });
      }).pipe(respondRiddleFailures),
    );
    yield* router.add(
      routes.guessRiddle.method,
      routes.guessRiddle.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { id } = yield* HttpRouter.schemaPathParams(RiddleParams);
        const request = yield* HttpServerRequest.schemaBodyJson(GuessRiddleRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, guessSizeLimit),
        );
        const command: RiddleCommand = { _tag: "Guess", riddle: id, ...request };
        const { riddle, right } = yield* changedOf(yield* riddles.run(userId, command));
        return yield* respondGuess({ riddle, right: right === true }, { headers });
      }).pipe(respondRiddleFailures),
    );
    yield* router.add(
      routes.hintRiddle.method,
      routes.hintRiddle.path,
      oneRiddle((riddle) => ({ _tag: "Hint", riddle })),
    );
    yield* router.add(
      routes.giveUpRiddle.method,
      routes.giveUpRiddle.path,
      oneRiddle((riddle) => ({ _tag: "GiveUp", riddle })),
    );
  }),
).pipe(Layer.orDie);
