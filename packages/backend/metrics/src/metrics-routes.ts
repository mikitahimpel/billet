import { Effect, Layer, Option } from "effect";
import { Digest } from "effect/crypto";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures } from "@billet/backend-auth/auth-routes";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { ReportEventsRequest } from "@billet/contracts-http-api/events";
import { routes } from "@billet/contracts-http-api/routes";
import { clientInfoOf, EventSink, pairHashOf, PairVariants, variantsLabel } from "./analytics.ts";
import { Metrics } from "./metrics.ts";

/**
 * The route the app reports its few named events to. Each accepted event is counted in D1 and
 * written to Analytics Engine. Needs `AuthService`, `Metrics`, `PairingRepository`, `EventSink`,
 * `PairVariants` and `Digest`.
 */
export const MetricsRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const metrics = yield* Metrics;
    const pairing = yield* PairingRepository;
    const principal = principalOf(yield* AuthService);
    const sink = yield* EventSink;
    const pairVariants = yield* PairVariants;
    const digest = yield* Digest.Digest;

    yield* router.add(
      routes.reportEvents.method,
      routes.reportEvents.path,
      Effect.gen(function* () {
        const { userId } = yield* principal;
        const { events } = yield* HttpServerRequest.schemaBodyJson(ReportEventsRequest);
        if (events.length === 0) return HttpServerResponse.empty({ status: 204 });
        // A directory failure only costs the pair on these counts; the events are still counted.
        const pairId = yield* pairing.findPair(userId).pipe(
          Effect.map(Option.getOrUndefined),
          Effect.catch(() => Effect.succeed(undefined)),
        );
        yield* Effect.forEach(events, (name) => metrics.record({ userId, pairId, name }), {
          discard: true,
        });

        const { appVersion, os } = clientInfoOf(
          (yield* HttpServerRequest.HttpServerRequest).headers,
        );
        const pairHash =
          pairId === undefined
            ? ""
            : yield* pairHashOf(pairId).pipe(Effect.provideService(Digest.Digest, digest));
        const variants = pairId === undefined ? "" : variantsLabel(yield* pairVariants.of(pairId));
        yield* Effect.forEach(
          events,
          (name) => sink.write({ name, pairHash, variants, appVersion, os }),
          { discard: true },
        );
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondFailures),
    );
  }),
).pipe(Layer.orDie);
