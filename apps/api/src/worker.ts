// Composition root of the `Api` Worker: wires platform pieces together and holds no logic.
import { DemoRoom } from "@billet/backend-platform/demo-room-durable-object";
import { routeDemo } from "@billet/backend-platform/demo-route";
import { PairRoom } from "@billet/backend-platform/pair-room-durable-object";
import { respondPlaceholder } from "@billet/backend-platform/placeholder-fetch";
import type { WorkerEnv } from "@billet/backend-platform/worker-env";

export { DemoRoom, PairRoom };

export default {
  fetch: (request, env) => routeDemo(request, env.DEMO_ROOM) ?? respondPlaceholder(),
} satisfies ExportedHandler<WorkerEnv>;
