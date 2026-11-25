import { ByteSize, Effect, Layer, Redacted, Schema } from "effect";
import {
  HttpIncomingMessage,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
} from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { PairId } from "@billet/contracts-domain/pair-id";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { clientInfoOf } from "@billet/contracts-http-api/client-info";
import {
  MockPlusRequest,
  OpenParcelRequest,
  OpenParcelResponse,
  PlusResponse,
  SubscribeRequest,
} from "@billet/contracts-http-api/plus";
import { routes } from "@billet/contracts-http-api/routes";
import { PaymentsConfig } from "./payments-config.ts";
import {
  type InvalidPurchase,
  type ParcelOpened,
  type ParcelRefused,
  PaymentsNotFound,
  type PaymentsUnavailable,
  type PieceOwned,
  type SubscriptionTaken,
} from "./payments-error.ts";
import { PaymentsService } from "./payments-service.ts";
import { PlusGate } from "./plus-gate.ts";
import { PlusService } from "./plus-service.ts";

const signedSizeLimit = ByteSize.kibibytes(64);

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondPlus = HttpServerResponse.schemaJson(PlusResponse);
const respondOpened = HttpServerResponse.schemaJson(OpenParcelResponse);

const noStore = { "cache-control": "no-store" };

const decodePairId = Schema.decodeSync(PairId);

const respondPlusFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    | RouteFailure
    | InvalidPurchase
    | PaymentsNotFound
    | PaymentsUnavailable
    | SubscriptionTaken
    | ParcelOpened
    | ParcelRefused
    | PieceOwned,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      InvalidPurchase: ({ reason }) =>
        Effect.annotateCurrentSpan("purchase.refused", reason).pipe(
          Effect.andThen(respondError(ApiError.cases.InvalidPurchase.make({}), { status: 400 })),
        ),
      PaymentsNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      SubscriptionTaken: () =>
        respondError(ApiError.cases.SubscriptionTaken.make({}), { status: 409 }),
      ParcelOpened: () => respondError(ApiError.cases.ParcelOpened.make({}), { status: 409 }),
      ParcelRefused: ({ reason }) =>
        Effect.annotateCurrentSpan("parcel.refused", reason).pipe(
          Effect.andThen(respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 })),
        ),
      PieceOwned: ({ itemId }) =>
        respondError(ApiError.cases.AlreadyOwned.make({ itemId }), { status: 409 }),
      PaymentsUnavailable: (error) =>
        Effect.logError("plus unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/**
 * Every `/v1/plus*` route is a 404, before the body is read, while the `plus` flag is off for the
 * caller's pair or the caller said they are 13 to 17: Plus is not offered to them. The mock route
 * exists only with the dev extras on. Apple's notifications reach Plus through the payments
 * notification route, which no flag closes.
 */
export const PlusRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const plus = yield* PlusService;
    const payments = yield* PaymentsService;
    const gate = yield* PlusGate;
    const { devTools } = yield* PaymentsConfig;
    const principal = principalOf(yield* AuthService);

    const caller = Effect.gen(function* () {
      const { userId } = yield* principal;
      const pairId = decodePairId(yield* payments.ownerOf(userId));
      const { appVersion } = clientInfoOf((yield* HttpServerRequest.HttpServerRequest).headers);
      const closed = yield* gate.closedFor(userId, pairId, appVersion);
      if (closed !== undefined) {
        yield* Effect.annotateCurrentSpan("plus.closed", closed);
        return yield* new PaymentsNotFound();
      }
      return { userId, pairId };
    });

    const body = <A>(schema: Schema.ConstraintDecoder<A, never>) =>
      HttpServerRequest.schemaBodyJson(schema).pipe(
        Effect.provideService(HttpIncomingMessage.MaxBodySize, signedSizeLimit),
      );

    yield* router.add(
      routes.getPlus.method,
      routes.getPlus.path,
      Effect.gen(function* () {
        const { userId, pairId } = yield* caller;
        return yield* respondPlus(yield* plus.view(userId, pairId), { headers: noStore });
      }).pipe(respondPlusFailures),
    );

    yield* router.add(
      routes.subscribePlus.method,
      routes.subscribePlus.path,
      Effect.gen(function* () {
        const { userId, pairId } = yield* caller;
        const request = yield* body(SubscribeRequest);
        const result = yield* plus.subscribe(
          userId,
          pairId,
          Redacted.make(request.signedTransaction),
          request.signedRenewalInfo === undefined
            ? undefined
            : Redacted.make(request.signedRenewalInfo),
        );
        return yield* respondPlus(result, { headers: noStore });
      }).pipe(respondPlusFailures),
    );

    if (devTools) {
      yield* router.add(
        routes.mockPlus.method,
        routes.mockPlus.path,
        Effect.gen(function* () {
          const { userId, pairId } = yield* caller;
          const request = yield* body(MockPlusRequest);
          return yield* respondPlus(yield* plus.mock(userId, pairId, request), {
            headers: noStore,
          });
        }).pipe(respondPlusFailures),
      );
    }

    yield* router.add(
      routes.openParcel.method,
      routes.openParcel.path,
      Effect.gen(function* () {
        const { userId, pairId } = yield* caller;
        const request = yield* body(OpenParcelRequest);
        return yield* respondOpened(yield* plus.openParcel(userId, pairId, request), {
          headers: noStore,
        });
      }).pipe(respondPlusFailures),
    );
  }),
).pipe(Layer.orDie);
