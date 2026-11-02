import { Effect, Layer, Option } from "effect";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { AuthService } from "@billet/backend-auth/auth-service";
import { principalOf, respondFailures } from "@billet/backend-auth/auth-routes";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { ReportEventsRequest } from "@billet/contracts-http-api/events";
import { routes } from "@billet/contracts-http-api/routes";
import { Metrics } from "./metrics.ts";

/** The route the app reports its few named events to. Needs `AuthService`, `Metrics` and `PairingRepository`. */
export const MetricsRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const metrics = yield* Metrics;
    const pairing = yield* PairingRepository;
    const principal = principalOf(yield* AuthService);

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
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(respondFailures),
    );
  }),
).pipe(Layer.orDie);
