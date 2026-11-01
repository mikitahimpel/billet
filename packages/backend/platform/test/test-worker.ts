import { DurableObject } from "cloudflare:workers";
import { Effect } from "effect";
import { respondApi } from "../src/api-fetch.ts";
import { openRoomDatabase } from "../src/room-database.ts";

import type { RoomMigrations } from "../src/room-database.ts";

// The Worker under test: exports the object class, as apps/api/src/worker.ts does.
export { PairRoom } from "../src/pair-room-durable-object.ts";

const migrateOnActivation = (ctx: DurableObjectState, migrations?: RoomMigrations) =>
  void ctx.blockConcurrencyWhile(() =>
    Effect.runPromise(Effect.scoped(openRoomDatabase(ctx.storage, migrations)).pipe(Effect.asVoid)),
  );

/** Opens its database the way `PairRoom` will once it moves to Drizzle (#67). */
export class ActivatedRoom extends DurableObject {
  constructor(ctx: DurableObjectState, env: never) {
    super(ctx, env);
    migrateOnActivation(ctx);
  }
}

/** An object that never migrates, to stand in for a room made by the earlier raw-SQL store. */
export class LegacyRoom extends DurableObject {}

/** The same object with a migration that cannot apply, to pin down what a bad deploy does. */
export class BrokenRoom extends DurableObject {
  constructor(ctx: DurableObjectState, env: never) {
    super(ctx, env);
    migrateOnActivation(ctx, { migrations: { "20260101000000_broken": "CREATE TABLE ;" } });
  }

  override fetch(): Response {
    return new Response("unreachable");
  }
}

export default { fetch: respondApi };
