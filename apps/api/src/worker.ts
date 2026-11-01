// Composition root of the `Api` Worker: wires platform pieces together and holds no logic.
import { DemoRoom } from "@billet/backend-platform/demo-room-durable-object";
import { routeDemo } from "@billet/backend-platform/demo-route";
import { respondApi } from "@billet/backend-platform/api-fetch";
import { PairRoom } from "@billet/backend-platform/pair-room-durable-object";
import type { WorkerEnv } from "@billet/backend-platform/worker-env";

export { DemoRoom, PairRoom };

export default {
  fetch: (request, env, ctx) => routeDemo(request, env.DEMO_ROOM) ?? respondApi(request, env, ctx),
} satisfies ExportedHandler<WorkerEnv>;
