import { Effect, Layer } from "effect";
import { routes } from "@billet/contracts-http-api/routes";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures, type RouteFailure } from "@billet/backend-auth/auth-routes";
import { ApiError } from "@billet/contracts-http-api/api-error";
import {
  ClaimInviteRequest,
  ClaimInviteResponse,
  CreateInviteResponse,
} from "@billet/contracts-http-api/invite";
import { PairResponse } from "@billet/contracts-http-api/pair";
import { ReportPartnerRequest } from "@billet/contracts-http-api/safety";
import type {
  AlreadyPaired,
  InvalidInvite,
  NotPaired,
  PairingUnavailable,
} from "./pairing-error.ts";
import { PairingService } from "./pairing-service.ts";

const respondError = HttpServerResponse.schemaJson(ApiError);
const respondInvite = HttpServerResponse.schemaJson(CreateInviteResponse);
const respondClaim = HttpServerResponse.schemaJson(ClaimInviteResponse);
const respondPair = HttpServerResponse.schemaJson(PairResponse);

/** An invite code is a one-time credential. */
const noStore = { "cache-control": "no-store" };

const respondPairingFailures = <R>(
  effect: Effect.Effect<
    HttpServerResponse.HttpServerResponse,
    RouteFailure | InvalidInvite | AlreadyPaired | NotPaired | PairingUnavailable,
    R
  >,
) =>
  effect.pipe(
    Effect.catchTags({
      InvalidInvite: () => respondError(ApiError.cases.InvalidInvite.make({}), { status: 404 }),
      AlreadyPaired: () => respondError(ApiError.cases.AlreadyPaired.make({}), { status: 409 }),
      NotPaired: () => respondError(ApiError.cases.NotFound.make({}), { status: 404 }),
      PairingUnavailable: (error) =>
        Effect.logError("pairing unavailable", error).pipe(
          Effect.andThen(respondError(ApiError.cases.Unavailable.make({}), { status: 503 })),
        ),
    }),
    respondFailures,
  );

export const PairingRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const pairing = yield* PairingService;
    const principal = principalOf(yield* AuthService);

    yield* router.add(
      routes.createInvite.method,
      routes.createInvite.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const invite = yield* pairing.createInvite(userId);
        return yield* respondInvite(invite, { headers: noStore });
      }).pipe(respondPairingFailures),
    );

    yield* router.add(
      routes.claimInvite.method,
      routes.claimInvite.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { code } = yield* HttpServerRequest.schemaBodyJson(ClaimInviteRequest);
        const pairId = yield* pairing.claimInvite(userId, code);
        return yield* respondClaim({ pairId });
      }).pipe(respondPairingFailures),
    );

    // Never cached: a partner who unpairs ends it for both on the next read.
    yield* router.add(
      routes.getPair.method,
      routes.getPair.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        return yield* respondPair(yield* pairing.pair(userId), { headers: noStore });
      }).pipe(respondPairingFailures),
    );

    // Idempotent: a client that lost the response can retry, and either partner can call it.
    yield* router.add(
      routes.unpair.method,
      routes.unpair.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        yield* pairing.unpair(userId);
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondPairingFailures),
    );

    yield* router.add(
      routes.blockPartner.method,
      routes.blockPartner.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        yield* pairing.blockPartner(userId);
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondPairingFailures),
    );

    yield* router.add(
      routes.reportPartner.method,
      routes.reportPartner.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const request = yield* HttpServerRequest.schemaBodyJson(ReportPartnerRequest);
        yield* pairing.reportPartner(userId, request);
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondPairingFailures),
    );
  }),
).pipe(Layer.orDie);
