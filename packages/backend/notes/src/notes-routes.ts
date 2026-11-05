import { ByteSize, Effect, Layer, Schema } from "effect";
import {
  HttpIncomingMessage,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
} from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { CoinEntryId } from "@billet/contracts-domain/coins";
import { MediaKey } from "@billet/contracts-domain/ids";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { BuyRequest, BuyResponse, CoinsResponse } from "@billet/contracts-http-api/coins";
import { InksResponse } from "@billet/contracts-http-api/inks";
import { routes } from "@billet/contracts-http-api/routes";
import {
  ListNotesResponse,
  SendNoteRequest,
  SendNoteResponse,
  UploadImageResponse,
} from "@billet/contracts-http-api/note";
import type {
  AlreadyOwned,
  InkNotOwned,
  InvalidNote,
  NotEnoughCoins,
  NotesNotFound,
  NotesUnavailable,
} from "./notes-error.ts";
import { contentTypeOf } from "./image-type.ts";
import { NotesService } from "./notes-service.ts";

/**
 * The most one image may take, a PNG drawing or a JPEG or HEIC photo alike. A rendered note or a
 * photo the app has resized fits, and a Worker holds the whole image in memory.
 */
export const imageSizeLimit = ByteSize.mebibytes(10);

/**
 * A note is at most a 3 KB compact rendition, or a photo's key, size, BlurHash (at most 166
 * characters) and 120-character caption, so anything larger is over budget anyway.
 */
const noteSizeLimit = ByteSize.kibibytes(16);

export const historyPageLimit = 100;

const decimal = Schema.NumberFromString.check(Schema.isInt());

const HistoryQuery = Schema.Struct({
  after: Schema.optionalKey(decimal.check(Schema.isGreaterThanOrEqualTo(0))),
  limit: Schema.optionalKey(
    decimal.check(Schema.isBetween({ minimum: 1, maximum: historyPageLimit })),
  ),
});

export const coinsPageLimit = 100;

const CoinsQuery = Schema.Struct({
  after: Schema.optionalKey(CoinEntryId),
  limit: Schema.optionalKey(
    decimal.check(Schema.isBetween({ minimum: 1, maximum: coinsPageLimit })),
  ),
});

/** A buy request is an id and an item name. */
const buySizeLimit = ByteSize.kibibytes(1);

const decodeMediaKey = Schema.decodeUnknownEffect(MediaKey);

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondUpload = HttpServerResponse.schemaJson(UploadImageResponse);
const respondNote = HttpServerResponse.schemaJson(SendNoteResponse);
const respondNotes = HttpServerResponse.schemaJson(ListNotesResponse);
const respondInks = HttpServerResponse.schemaJson(InksResponse);
const respondCoins = HttpServerResponse.schemaJson(CoinsResponse);
const respondBuy = HttpServerResponse.schemaJson(BuyResponse);

/** The path carries a key from the signed-in couple's prefix, so nothing here may be cached. */
const imageHeaders = { "cache-control": "no-store", "x-content-type-options": "nosniff" };

const respondNotesFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    | RouteFailure
    | NotesNotFound
    | InvalidNote
    | InkNotOwned
    | NotEnoughCoins
    | AlreadyOwned
    | NotesUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      NotesNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      InvalidNote: () => respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 }),
      InkNotOwned: ({ ink }) =>
        respondError(ApiError.cases.InkNotOwned.make({ ink }), { status: 400 }),
      NotEnoughCoins: ({ needed, have }) =>
        respondError(ApiError.cases.NotEnoughCoins.make({ needed, have }), { status: 409 }),
      AlreadyOwned: ({ ink }) =>
        respondError(ApiError.cases.AlreadyOwned.make({ itemId: ink }), { status: 409 }),
      NotesUnavailable: (error) =>
        Effect.logError("notes unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/** The notes and media routes of the API. Needs `AuthService` and `NotesService`. */
export const NotesRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const notes = yield* NotesService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.uploadImage.method,
      routes.uploadImage.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.HttpServerRequest;
        const body = yield* request.arrayBuffer.pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, imageSizeLimit),
        );
        const image = yield* notes.uploadImage(userId, new Uint8Array(body));
        return yield* respondUpload({ image });
      }).pipe(respondNotesFailures),
    );

    // A key has slashes in it, so it is the rest of the path.
    yield* router.add(
      routes.downloadImage.method,
      routes.downloadImage.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const params = yield* HttpRouter.params;
        const key = yield* decodeMediaKey(params["*"]);
        const bytes = yield* notes.readImage(userId, key);
        return HttpServerResponse.uint8Array(bytes, {
          contentType: contentTypeOf(key),
          headers: imageHeaders,
        });
      }).pipe(respondNotesFailures),
    );

    yield* router.add(
      routes.sendNote.method,
      routes.sendNote.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(SendNoteRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, noteSizeLimit),
        );
        const note = yield* notes.sendNote(userId, request);
        return yield* respondNote({ note });
      }).pipe(respondNotesFailures),
    );

    // `after` is the last `seq` the client holds. Each entry carries its `seq`, so the next page
    // starts after the last one.
    yield* router.add(
      routes.listNotes.method,
      routes.listNotes.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { after = 0, limit = historyPageLimit } =
          yield* HttpServerRequest.schemaSearchParams(HistoryQuery);
        const page = yield* notes.history(userId, after, limit);
        return yield* respondNotes({ notes: page });
      }).pipe(respondNotesFailures),
    );

    // Never cached: a colour bought on the partner's phone shows up on the next read.
    yield* router.add(
      routes.listInks.method,
      routes.listInks.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        return yield* respondInks(yield* notes.inks(userId), {
          headers: { "cache-control": "no-store" },
        });
      }).pipe(respondNotesFailures),
    );

    // The wallet is the pair's: never cached, so a partner's buy or earn shows on the next read.
    yield* router.add(
      routes.getCoins.method,
      routes.getCoins.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { after, limit = coinsPageLimit } =
          yield* HttpServerRequest.schemaSearchParams(CoinsQuery);
        return yield* respondCoins(yield* notes.coins(userId, after, limit), {
          headers: { "cache-control": "no-store" },
        });
      }).pipe(respondNotesFailures),
    );

    yield* router.add(
      routes.buyItem.method,
      routes.buyItem.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(BuyRequest).pipe(
          Effect.provideService(HttpIncomingMessage.MaxBodySize, buySizeLimit),
        );
        return yield* respondBuy(yield* notes.buy(userId, request));
      }).pipe(respondNotesFailures),
    );
  }),
).pipe(Layer.orDie);
