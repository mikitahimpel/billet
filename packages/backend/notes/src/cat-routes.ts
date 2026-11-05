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
  CatJournalResponse,
  CatResponse,
  RecordCatEventRequest,
  RecordCatEventResponse,
  SaveCatRequest,
} from "@billet/contracts-http-api/cat";
import { routes } from "@billet/contracts-http-api/routes";
import { CatService } from "./cat-service.ts";
import type { InvalidNote, NotesNotFound, NotesUnavailable } from "./notes-error.ts";

/** A cat request is a name, a look and a few numbers. */
const bodySizeLimit = ByteSize.kibibytes(2);

export const journalPageLimit = 100;

const decimal = Schema.NumberFromString.check(Schema.isInt());

const JournalQuery = Schema.Struct({
  after: Schema.optionalKey(decimal.check(Schema.isGreaterThanOrEqualTo(0))),
  limit: Schema.optionalKey(
    decimal.check(Schema.isBetween({ minimum: 1, maximum: journalPageLimit })),
  ),
});

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondCat = HttpServerResponse.schemaJson(CatResponse);
const respondRecord = HttpServerResponse.schemaJson(RecordCatEventResponse);
const respondJournal = HttpServerResponse.schemaJson(CatJournalResponse);

const respondCatFailures = <R>(
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
        Effect.logError("cat unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

const limited = Effect.provideService(HttpIncomingMessage.MaxBodySize, bodySizeLimit);

/** The cat routes of the API. Needs `AuthService` and `CatService`. */
export const CatRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const cat = yield* CatService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.getCat.method,
      routes.getCat.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        return yield* respondCat(yield* cat.read(userId));
      }).pipe(respondCatFailures),
    );

    yield* router.add(
      routes.saveCat.method,
      routes.saveCat.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(SaveCatRequest).pipe(limited);
        return yield* respondCat(yield* cat.save(userId, request));
      }).pipe(respondCatFailures),
    );

    yield* router.add(
      routes.recordCatEvent.method,
      routes.recordCatEvent.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request =
          yield* HttpServerRequest.schemaBodyJson(RecordCatEventRequest).pipe(limited);
        return yield* respondRecord(yield* cat.record(userId, request));
      }).pipe(respondCatFailures),
    );

    yield* router.add(
      routes.listCatJournal.method,
      routes.listCatJournal.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { after = 0, limit = journalPageLimit } =
          yield* HttpServerRequest.schemaSearchParams(JournalQuery);
        return yield* respondJournal({ entries: yield* cat.journal(userId, after, limit) });
      }).pipe(respondCatFailures),
    );
  }),
).pipe(Layer.orDie);
