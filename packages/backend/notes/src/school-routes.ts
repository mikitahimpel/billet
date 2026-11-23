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
import { LessonRequest, RoutineRequest, SchoolResponse } from "@billet/contracts-http-api/school";
import { routes } from "@billet/contracts-http-api/routes";
import { SchoolService } from "./school-service.ts";
import type { InvalidSchool, NotesNotFound, NotesUnavailable } from "./notes-error.ts";

/** A routine is at most five short ids. */
const bodySizeLimit = ByteSize.kibibytes(4);

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondSchool = HttpServerResponse.schemaJson(SchoolResponse);
const headers = { "cache-control": "no-store" };

const respondSchoolFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | NotesNotFound | InvalidSchool | NotesUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      InvalidSchool: () => respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 }),
      NotesNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      NotesUnavailable: (error) =>
        Effect.logError("school unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/** The cat school routes of the API. Needs `AuthService` and `SchoolService`. */
export const SchoolRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const school = yield* SchoolService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.getSchool.method,
      routes.getSchool.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        return yield* respondSchool(yield* school.run(userId, { _tag: "View" }), { headers });
      }).pipe(respondSchoolFailures),
    );
    yield* router.add(
      routes.teachTrick.method,
      routes.teachTrick.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(LessonRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit),
        );
        const view = yield* school.run(userId, { _tag: "Lesson", ...request });
        return yield* respondSchool(view, { headers });
      }).pipe(respondSchoolFailures),
    );
    yield* router.add(
      routes.sendRoutine.method,
      routes.sendRoutine.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(RoutineRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit),
        );
        const view = yield* school.run(userId, { _tag: "Routine", ...request });
        return yield* respondSchool(view, { headers });
      }).pipe(respondSchoolFailures),
    );
  }),
).pipe(Layer.orDie);
