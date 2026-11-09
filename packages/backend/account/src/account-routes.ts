import { Effect, Layer, Option, Redacted } from "effect";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { AuthService } from "@billet/backend-auth/auth-service";
import { DeleteAccountRequest } from "@billet/contracts-http-api/account";
import { ApiError } from "@billet/contracts-http-api/api-error";
import { routes } from "@billet/contracts-http-api/routes";
import { AccountDeletion } from "./account-deletion.ts";
import type { AccountUnavailable } from "./account-error.ts";

const respondError = HttpServerResponse.schemaJson(ApiError);

const respondAccountFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | AccountUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTag("AccountUnavailable", (error) =>
      Effect.logError("account unavailable", error).pipe(
        Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
      ),
    ),
    respondFailures,
  );

export const AccountRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const deletion = yield* AccountDeletion;
    const principal = principalOf(yield* AuthService);

    // A retry after a lost response is refused as unauthorized: the account and its sessions are
    // gone, which is the answer the app needs.
    yield* router.add(
      routes.deleteAccount.method,
      routes.deleteAccount.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const body = yield* HttpServerRequest.schemaBodyJson(DeleteAccountRequest);
        const code = Option.map(Option.fromNullishOr(body.appleAuthorizationCode), Redacted.make);
        yield* deletion.deleteAccount(userId, code);
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondAccountFailures),
    );
  }),
).pipe(Layer.orDie);
