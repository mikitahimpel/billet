// The Worker under test: exports the object class, as apps/api/src/worker.ts does.
export { PairRoom } from "../src/pair-room-durable-object.ts";

export default {
  fetch: () => new Response(null, { status: 404 }),
};
