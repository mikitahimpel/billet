import { ByteSize, Effect, Layer, Redacted, type Schema } from "effect";
import {
  HttpIncomingMessage,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
} from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { AuthRejected } from "@billet/backend-auth/auth-error";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { ApiError } from "@billet/contracts-http-api/api-error";
import {
  AppStoreNotificationRequest,
  MockPurchaseRequest,
  PurchaseRequest,
  PurchaseResponse,
  StampsResponse,
} from "@billet/contracts-http-api/purchase";
import { authorizationHeader, demoRoomHeader, routes } from "@billet/contracts-http-api/routes";
import { PaymentsConfig } from "./payments-config.ts";
import type { InvalidPurchase, PaymentsNotFound, PaymentsUnavailable } from "./payments-error.ts";
import { demoOwner, PaymentsService } from "./payments-service.ts";

/** A signed transaction or notification is a few kilobytes: its certificate chain and claims. */
const signedSizeLimit = ByteSize.kibibytes(64);

const demoRoomCode = /^[A-Za-z0-9_-]{1,64}$/;

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondPurchase = HttpServerResponse.schemaJson(PurchaseResponse);
const respondStamps = HttpServerResponse.schemaJson(StampsResponse);

const noStore = { "cache-control": "no-store" };

const respondPaymentsFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | InvalidPurchase | PaymentsNotFound | PaymentsUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      // A client error, so not a log line; the fixed reason goes on the span for the trace.
      InvalidPurchase: ({ reason }) =>
        Effect.annotateCurrentSpan("purchase.refused", reason).pipe(
          Effect.andThen(respondError(ApiError.cases.InvalidPurchase.make({}), { status: 400 })),
        ),
      PaymentsNotFound: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      PaymentsUnavailable: (error) =>
        Effect.logError("payments unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

/**
 * The purchase and stamp routes of the API. Needs `AuthService`, `PaymentsService` and
 * `PaymentsConfig`. The mock purchase route exists only with the dev extras on; elsewhere it is
 * the router's 404 for a path it doesn't know.
 */
export const PaymentsRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const payments = yield* PaymentsService;
    const { devTools } = yield* PaymentsConfig;
    const principal = principalOf(yield* AuthService);

    // A session names the pair. Without one, the dev stage takes a demo room's code instead, so
    // the app's demo mode has a ledger; every other stage asks for a session.
    const owner = Effect.gen(function* () {
      const { headers } = yield* HttpServerRequest.HttpServerRequest;
      const demoRoom = headers[demoRoomHeader];
      if (devTools && headers[authorizationHeader] === undefined && demoRoom !== undefined) {
        if (!demoRoomCode.test(demoRoom)) {
          return yield* new AuthRejected({ reason: "demo-room-malformed" });
        }
        return demoOwner(demoRoom);
      }
      const { userId } = yield* principal;
      return yield* payments.ownerOf(userId);
    });

    const body = <A>(schema: Schema.ConstraintDecoder<A, never>) =>
      HttpServerRequest.schemaBodyJson(schema).pipe(
        Effect.provideService(HttpIncomingMessage.MaxBodySize, signedSizeLimit),
      );

    yield* router.add(
      routes.purchase.method,
      routes.purchase.path,
      Effect.gen(function* () {
        const caller = yield* owner;
        const { signedTransaction } = yield* body(PurchaseRequest);
        const result = yield* payments.purchase(caller, Redacted.make(signedTransaction));
        return yield* respondPurchase(result, { headers: noStore });
      }).pipe(respondPaymentsFailures),
    );

    if (devTools) {
      yield* router.add(
        routes.mockPurchase.method,
        routes.mockPurchase.path,
        Effect.gen(function* () {
          const caller = yield* owner;
          const request = yield* body(MockPurchaseRequest);
          const result = yield* payments.mockPurchase(caller, request);
          return yield* respondPurchase(result, { headers: noStore });
        }).pipe(respondPaymentsFailures),
      );
    }

    yield* router.add(
      routes.getStamps.method,
      routes.getStamps.path,
      Effect.gen(function* () {
        const caller = yield* owner;
        return yield* respondStamps(yield* payments.stamps(caller), { headers: noStore });
      }).pipe(respondPaymentsFailures),
    );

    // Apple calls this, with no session: the signature is the authentication. Any answer but 200
    // makes Apple retry, so a notification that is handled, a duplicate or one that is only noted
    // all answer 200; a bad signature answers 400.
    yield* router.add(
      routes.appStoreNotifications.method,
      routes.appStoreNotifications.path,
      Effect.gen(function* () {
        const { signedPayload } = yield* body(AppStoreNotificationRequest);
        yield* payments.notification(Redacted.make(signedPayload));
        return HttpServerResponse.jsonUnsafe({}, { headers: noStore });
      }).pipe(respondPaymentsFailures),
    );
  }),
).pipe(Layer.orDie);
