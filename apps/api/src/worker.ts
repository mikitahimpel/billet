// Composition root of the `Api` Worker: wires platform pieces together and holds no logic.
import { respondApi } from "@billet/backend-platform/api-fetch";
import { PairRoom } from "@billet/backend-platform/pair-room-durable-object";
import type { WorkerEnv } from "@billet/backend-platform/worker-env";

export { PairRoom };

export default {
  fetch: respondApi,
} satisfies ExportedHandler<WorkerEnv>;
