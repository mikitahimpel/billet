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
import { clientInfoOf } from "@billet/contracts-http-api/client-info";
import {
  AppStoreNotificationRequest,
  MockPurchaseRequest,
  PurchaseRequest,
  PurchaseResponse,
  PurchasesResponse,
} from "@billet/contracts-http-api/purchase";
import { authorizationHeader, demoRoomHeader, routes } from "@billet/contracts-http-api/routes";
import { PaymentsConfig } from "./payments-config.ts";
import type { InvalidPurchase, PaymentsUnavailable } from "./payments-error.ts";
import { PaymentsNotFound } from "./payments-error.ts";
import { demoOwner, PaymentsService } from "./payments-service.ts";
import { PaymentsSwitch } from "./payments-switch.ts";

/** A signed transaction or notification is a few kilobytes: its certificate chain and claims. */
const signedSizeLimit = ByteSize.kibibytes(64);

const demoRoomCode = /^[A-Za-z0-9_-]{1,64}$/;

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondPurchase = HttpServerResponse.schemaJson(PurchaseResponse);
const respondPurchases = HttpServerResponse.schemaJson(PurchasesResponse);

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

/** The mock purchase route exists only with the dev extras on. While the `payments` flag is off
 * for the caller, every `/v1/purchases*` route answers 404, before it reads the body. */
export const PaymentsRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const payments = yield* PaymentsService;
    const paymentsSwitch = yield* PaymentsSwitch;
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

    // The owner of a purchase route, once the `payments` flag lets it in. Off: a 404, the same
    // answer as a path that does not exist.
    const buyer = Effect.gen(function* () {
      const caller = yield* owner;
      const { appVersion } = clientInfoOf((yield* HttpServerRequest.HttpServerRequest).headers);
      if (!(yield* paymentsSwitch.enabledFor(caller, appVersion))) {
        return yield* new PaymentsNotFound();
      }
      return caller;
    });

    const body = <A>(schema: Schema.ConstraintDecoder<A, never>) =>
      HttpServerRequest.schemaBodyJson(schema).pipe(
        Effect.provideService(HttpIncomingMessage.MaxBodySize, signedSizeLimit),
      );

    yield* router.add(
      routes.purchase.method,
      routes.purchase.path,
      Effect.gen(function* () {
        const caller = yield* buyer;
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
          const caller = yield* buyer;
          const request = yield* body(MockPurchaseRequest);
          const result = yield* payments.mockPurchase(caller, request);
          return yield* respondPurchase(result, { headers: noStore });
        }).pipe(respondPaymentsFailures),
      );
    }

    yield* router.add(
      routes.getPurchases.method,
      routes.getPurchases.path,
      Effect.gen(function* () {
        const caller = yield* buyer;
        return yield* respondPurchases(yield* payments.purchases(caller), { headers: noStore });
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
