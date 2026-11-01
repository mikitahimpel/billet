import { Effect, Layer, Redacted, type Schema } from "effect";
import {
  type HttpBody,
  HttpRouter,
  HttpServerRequest,
  HttpServerResponse,
  type HttpServerError,
} from "effect/http";
import { ApiError } from "@billet/contracts-http-api/api-error";
import {
  AuthChallengeResponse,
  SessionResponse,
  SignInWithAppleRequest,
} from "@billet/contracts-http-api/auth";
import { RegisterPushTokenRequest } from "@billet/contracts-http-api/device";
import { AuthRejected, type AuthUnavailable } from "./auth-error.ts";
import { AuthService, type Principal } from "./auth-service.ts";

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondChallenge = HttpServerResponse.schemaJson(AuthChallengeResponse);
const respondSession = HttpServerResponse.schemaJson(SessionResponse);

/** These responses carry credentials or one-time values. */
const noStore = { "cache-control": "no-store" };

type RouteFailure =
  | AuthRejected
  | AuthUnavailable
  | HttpBody.HttpBodyError
  | HttpServerError.HttpServerError
  | Schema.SchemaError;

/**
 * The one place failures become responses. Logs carry fixed labels only: never a token, a header
 * or a schema error, whose message can quote the input.
 */
const respondFailures = <R>(
  effect: Effect.Effect<HttpServerResponse.HttpServerResponse, RouteFailure, R>,
) =>
  effect.pipe(
    Effect.catchTags({
      AuthRejected: ({ reason }) =>
        Effect.logInfo("auth rejected", reason).pipe(
          Effect.andThen(respondError(ApiError.cases.Unauthorized.make({}), { status: 401 })),
        ),
      AuthUnavailable: ({ reason }) =>
        Effect.logError("auth unavailable", reason).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    Effect.catch(() => respondError(ApiError.cases.InvalidRequest.make({}), { status: 400 })),
    Effect.orDie,
  );

const bearerPrefix = "Bearer ";

const bearerToken = Effect.gen(function* () {
  const { headers } = yield* HttpServerRequest.HttpServerRequest;
  const header = headers["authorization"];
  return header?.startsWith(bearerPrefix)
    ? Redacted.make(header.slice(bearerPrefix.length))
    : yield* new AuthRejected({ reason: "bearer-missing" });
});

/** The auth and device routes of the API. Needs `AuthService`, which the Worker composes. */
export const AuthRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const auth = yield* AuthService;

    const principal: Effect.Effect<
      Principal,
      AuthRejected | AuthUnavailable,
      HttpServerRequest.HttpServerRequest
    > = Effect.flatMap(bearerToken, auth.authenticate);

    yield* router.add(
      "POST",
      "/v1/auth/challenge",
      Effect.flatMap(auth.issueChallenge, (challenge) =>
        respondChallenge(challenge, { headers: noStore }),
      ).pipe(respondFailures),
    );

    yield* router.add(
      "POST",
      "/v1/auth/apple",
      Effect.gen(function* () {
        const body = yield* HttpServerRequest.schemaBodyJson(SignInWithAppleRequest);
        const session = yield* auth.signInWithApple(Redacted.make(body.identityToken));
        return yield* respondSession(session, { headers: noStore });
      }).pipe(respondFailures),
    );

    yield* router.add(
      "POST",
      "/v1/auth/sign-out",
      Effect.gen(function* () {
        yield* auth.signOut(yield* principal);
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondFailures),
    );

    yield* router.add(
      "PUT",
      "/v1/devices/current/push-token",
      Effect.gen(function* () {
        const caller = yield* principal;
        const body = yield* HttpServerRequest.schemaBodyJson(RegisterPushTokenRequest);
        yield* auth.registerPushToken(caller, body);
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondFailures),
    );
  }),
).pipe(Layer.orDie);
