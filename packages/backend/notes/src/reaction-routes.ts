import { ByteSize, Effect, Layer, Schema } from "effect";
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
  ListReactionsResponse,
  ReactRequest,
  ReactResponse,
} from "@billet/contracts-http-api/reaction";
import { routes } from "@billet/contracts-http-api/routes";
import { ReactionService } from "./reaction-service.ts";
import type { InvalidNote, NotesNotFound, NotesUnavailable } from "./notes-error.ts";

/** A reaction request is a note id and a word. */
const bodySizeLimit = ByteSize.kibibytes(1);

export const reactionsPageLimit = 100;

const decimal = Schema.NumberFromString.check(Schema.isInt());

const ListQuery = Schema.Struct({
  after: Schema.optionalKey(decimal.check(Schema.isGreaterThanOrEqualTo(0))),
  limit: Schema.optionalKey(
    decimal.check(Schema.isBetween({ minimum: 1, maximum: reactionsPageLimit })),
  ),
});

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondReact = HttpServerResponse.schemaJson(ReactResponse);
const respondList = HttpServerResponse.schemaJson(ListReactionsResponse);

const respondReactionFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | NotesNotFound | InvalidNote | NotesUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      NotesNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      InvalidNote: () => respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 }),
      NotesUnavailable: (error) =>
        Effect.logError("reactions unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

const limited = Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit);

/** The reaction routes of the API. Needs `AuthService` and `ReactionService`. */
export const ReactionRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const reactions = yield* ReactionService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.react.method,
      routes.react.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(ReactRequest).pipe(limited);
        return yield* respondReact({ reaction: yield* reactions.react(userId, request) });
      }).pipe(respondReactionFailures),
    );

    yield* router.add(
      routes.listReactions.method,
      routes.listReactions.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { after = 0, limit = reactionsPageLimit } =
          yield* HttpServerRequest.schemaSearchParams(ListQuery);
        return yield* respondList({ reactions: yield* reactions.list(userId, after, limit) });
      }).pipe(respondReactionFailures),
    );
  }),
).pipe(Layer.orDie);
