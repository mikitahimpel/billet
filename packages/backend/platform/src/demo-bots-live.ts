import { Effect, Layer } from "effect";
import { DemoBots } from "@billet/backend-demo-partner/demo-bots";
import { DemoPartnerUnavailable } from "@billet/backend-demo-partner/demo-partner-error";
import { spanMethods } from "@billet/backend-observability/span-methods";
import type { PairRoom } from "./pair-room-durable-object.ts";

const unavailable = (cause: unknown) =>
  new DemoPartnerUnavailable({ reason: "room-unavailable", cause });

/** The bot lives in its pair's `PairRoom`, on its alarm. */
export const DemoBotsLive = (rooms: DurableObjectNamespace<PairRoom>): Layer.Layer<DemoBots> =>
  Layer.succeed(
    DemoBots,
    DemoBots.of(
      spanMethods("DemoBots", {
        start: (pairId, owner, bot) =>
          Effect.tryPromise({
            try: () => rooms.getByName(pairId).startDemo(owner, bot),
            catch: unavailable,
          }),
        stop: (pairId) =>
          Effect.tryPromise({ try: () => rooms.getByName(pairId).stopDemo(), catch: unavailable }),
      }),
    ),
  );
