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
import { ChangeListRequest, ListsResponse } from "@billet/contracts-http-api/lists";
import { routes } from "@billet/contracts-http-api/routes";
import { ListsService } from "./lists-service.ts";
import type { NotesNotFound, NotesUnavailable } from "./notes-error.ts";

/** The largest change is one item with every detail. */
const bodySizeLimit = ByteSize.kibibytes(8);

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondLists = HttpServerResponse.schemaJson(ListsResponse);
const headers = { "cache-control": "no-store" };

const respondListFailures = <R>(
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
        Effect.logError("lists unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/** The list routes of the API. Needs `AuthService` and `ListsService`. */
export const ListsRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const lists = yield* ListsService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.getLists.method,
      routes.getLists.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        return yield* respondLists(yield* lists.run(userId, undefined), { headers });
      }).pipe(respondListFailures),
    );
    yield* router.add(
      routes.changeList.method,
      routes.changeList.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(ChangeListRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit),
        );
        return yield* respondLists(yield* lists.run(userId, request), { headers });
      }).pipe(respondListFailures),
    );
  }),
).pipe(Layer.orDie);
