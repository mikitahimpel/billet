import { Effect, Layer, Redacted, type Schema } from "effect";
import {
  type HttpBody,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
  type HttpServerError,
} from "effect/http";
import { AccountResponse } from "@billet/contracts-http-api/account";
import { ApiError } from "@billet/contracts-http-api/api-error";
import {
  AuthChallengeResponse,
  SessionResponse,
  SignInAnonymouslyRequest,
  SignInWithAppleRequest,
} from "@billet/contracts-http-api/auth";
import { RegisterPushTokenRequest } from "@billet/contracts-http-api/device";
import { authorizationHeader, bearerPrefix, routes } from "@billet/contracts-http-api/routes";
import { type AppleIdInUse, AuthRejected, type AuthUnavailable } from "./auth-error.ts";
import { AuthService, type Principal } from "./auth-service.ts";

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondChallenge = HttpServerResponse.schemaJson(AuthChallengeResponse);
const respondSession = HttpServerResponse.schemaJson(SessionResponse);
const respondAccount = HttpServerResponse.schemaJson(AccountResponse);

/** These responses carry credentials or one-time values. */
const noStore = { "cache-control": "no-store" };

export type RouteFailure =
  | AppleIdInUse
  | AuthRejected
  | AuthUnavailable
  | HttpBody.HttpBodyError
  | HttpServerError.HttpServerError
  | Schema.SchemaError;

/** Logs carry fixed labels only: never a token, a header or a schema error that quotes input. */
export const respondFailures = <R>(
  effect: Effect.Effect<HttpServerResponse.HttpServerResponse, RouteFailure, R>,
) =>
  effect.pipe(
    Effect.catchTags({
      AppleIdInUse: () =>
        respondError(ApiError.cases.AppleIdInUse.make({}), { status: 409, headers: noStore }),
      AuthRejected: ({ reason }) =>
        Effect.logInfo("auth rejected", reason).pipe(
          Effect.andThen(respondError(ApiError.cases.Unauthorized.make({}), { status: 401 })),
        ),
      AuthUnavailable: (error) =>
        Effect.logError("auth unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    Effect.catch(() => respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 })),
    Effect.orDie,
  );

const bearerToken = Effect.gen(function* () {
  const { headers } = yield* HttpServerRequest.HttpServerRequest;
  const header = headers[authorizationHeader];
  return header?.startsWith(bearerPrefix)
    ? Redacted.make(header.slice(bearerPrefix.length))
    : yield* new AuthRejected({ reason: "bearer-missing" });
});

/** The caller of the current request, from its bearer token. Check it before reading the body. */
export const principalOf = (
  auth: AuthService["Service"],
): Effect.Effect<Principal, AuthRejected | AuthUnavailable, HttpServerRequest.HttpServerRequest> =>
  Effect.flatMap(bearerToken, auth.authenticate);

export const AuthRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const auth = yield* AuthService;

    const principal = principalOf(auth);

    yield* router.add(
      routes.authChallenge.method,
      routes.authChallenge.path,
      Effect.flatMap(auth.issueChallenge, (challenge) =>
        respondChallenge(challenge, { headers: noStore }),
      ).pipe(respondFailures),
    );

    yield* router.add(
      routes.authAnonymous.method,
      routes.authAnonymous.path,
      Effect.gen(function* () {
        const body = yield* HttpServerRequest.schemaBodyJson(SignInAnonymouslyRequest);
        const session = yield* auth.signInAnonymously(Redacted.make(body.accountKey));
        return yield* respondSession(session, { headers: noStore });
      }).pipe(respondFailures),
    );

    yield* router.add(
      routes.authApple.method,
      routes.authApple.path,
      Effect.gen(function* () {
        const body = yield* HttpServerRequest.schemaBodyJson(SignInWithAppleRequest);
        const session = yield* auth.signInWithApple(Redacted.make(body.identityToken));
        return yield* respondSession(session, { headers: noStore });
      }).pipe(respondFailures),
    );

    yield* router.add(
      routes.authAppleLink.method,
      routes.authAppleLink.path,
      Effect.gen(function* () {
        const token = yield* bearerToken;
        // The caller is checked before the body is read, as on every authenticated route.
        yield* auth.authenticate(token);
        const body = yield* HttpServerRequest.schemaBodyJson(SignInWithAppleRequest);
        const account = yield* auth.linkApple(token, Redacted.make(body.identityToken));
        return yield* respondAccount(account, { headers: noStore });
      }).pipe(respondFailures),
    );

    yield* router.add(
      routes.getAccount.method,
      routes.getAccount.path,
      Effect.flatMap(bearerToken, auth.account).pipe(
        Effect.flatMap((account) => respondAccount(account, { headers: noStore })),
        respondFailures,
      ),
    );

    yield* router.add(
      routes.authSignOut.method,
      routes.authSignOut.path,
      Effect.gen(function* () {
        yield* auth.signOut(yield* principal);
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondFailures),
    );

    yield* router.add(
      routes.registerPushToken.method,
      routes.registerPushToken.path,
      Effect.gen(function* () {
        const caller = yield* principal;
        const body = yield* HttpServerRequest.schemaBodyJson(RegisterPushTokenRequest);
        yield* auth.registerPushToken(caller, body);
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondFailures),
    );
  }),
).pipe(Layer.orDie);
