import { Effect, Layer, Option } from "effect";
import { Digest } from "effect/crypto";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures } from "@billet/backend-auth/auth-routes";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { clientInfoOf } from "@billet/contracts-http-api/client-info";
import { clientEventOf, ReportEventsRequest } from "@billet/contracts-http-api/events";
import { routes } from "@billet/contracts-http-api/routes";
import { EventSink, pairHashOf, PairVariants, variantsLabel } from "./analytics.ts";
import { Metrics } from "./metrics.ts";

/**
 * Counts each event in D1 (its detail apart from the person) and writes it to Analytics Engine.
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
        const events = (yield* HttpServerRequest.schemaBodyJson(ReportEventsRequest)).events.map(
          clientEventOf,
        );
        if (events.length === 0) return HttpServerResponse.empty({ status: 204 });
        // A directory failure only costs the pair on these counts; the events are still counted.
        const pairId = yield* pairing.findPair(userId).pipe(
          Effect.map(Option.getOrUndefined),
          Effect.catch(() => Effect.succeed(undefined)),
        );
        const { appVersion, os } = clientInfoOf(
          (yield* HttpServerRequest.HttpServerRequest).headers,
        );
        yield* Effect.forEach(
          events,
          ({ name, detail, value }) =>
            metrics.record({ userId, pairId, name, detail, value, client: { appVersion, os } }),
          { discard: true },
        );

        const pairHash =
          pairId === undefined
            ? ""
            : yield* pairHashOf(pairId).pipe(Effect.provideService(Digest.Digest, digest));
        const variants = pairId === undefined ? "" : variantsLabel(yield* pairVariants.of(pairId));
        yield* Effect.forEach(
          events,
          ({ name, detail, value }) =>
            sink.write({
              name,
              pairHash,
              variants,
              appVersion,
              os,
              ...(detail === undefined ? {} : { detail }),
              ...(value === undefined ? {} : { value }),
            }),
          { discard: true },
        );
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondFailures),
    );
  }),
).pipe(Layer.orDie);
