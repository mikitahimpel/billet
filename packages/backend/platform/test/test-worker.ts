import { DurableObject } from "cloudflare:workers";
import { Effect } from "effect";
import { openRoomDatabase } from "../src/room-database.ts";

// The Worker under test: exports the object class, as apps/api/src/worker.ts does.
export { PairRoom } from "../src/pair-room-placeholder.ts";

/** A `PairRoom` whose migration cannot apply, to pin down what a bad deploy does. */
export class BrokenRoom extends DurableObject {
  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env as never);
    void ctx.blockConcurrencyWhile(() =>
      Effect.runPromise(
        Effect.scoped(
          openRoomDatabase(ctx.storage, {
            migrations: { "20260101000000_broken": "CREATE TABLE ;" },
          }),
        ).pipe(Effect.asVoid),
      ),
    );
  }

  override fetch(): Response {
    return new Response("unreachable");
  }
}

export default {
  fetch: () => new Response(null, { status: 404 }),
};
