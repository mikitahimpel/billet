import { DurableObject } from "cloudflare:workers";
import { Effect } from "effect";
import { openRoomDatabase } from "./room-database.ts";

// Placeholder for the `PairRoom` Durable Object, so the namespace exists on the first deploy.
// The reducer and the real adapter replace it in the PairRoom ticket.
export class PairRoom extends DurableObject {
  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env as never);
    // Migrate on activation, before any request reaches the object.
    void ctx.blockConcurrencyWhile(() =>
      Effect.runPromise(Effect.scoped(openRoomDatabase(ctx.storage).pipe(Effect.asVoid))),
    );
  }

  override fetch(): Response {
    return new Response("PairRoom is not implemented yet", { status: 501 });
  }
}
