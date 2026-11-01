// Composition root of the `Api` Worker: wires platform pieces together and holds no logic.
import { PairRoom } from "@billet/backend-platform/pair-room-durable-object";
import { respondPlaceholder } from "@billet/backend-platform/placeholder-fetch";
import type { WorkerEnv } from "@billet/backend-platform/worker-env";

export { PairRoom };

export default {
  fetch: () => respondPlaceholder(),
} satisfies ExportedHandler<WorkerEnv>;
