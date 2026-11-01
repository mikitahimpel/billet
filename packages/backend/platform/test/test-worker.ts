import { DurableObject } from "cloudflare:workers";
import { Effect } from "effect";
import { respondApi } from "../src/api-fetch.ts";
import { openRoomDatabase } from "../src/room-database.ts";

import type { RoomMigrations } from "../src/room-database.ts";

// The Worker under test: exports the object class, as apps/api/src/worker.ts does.
import { PairRoom } from "../src/pair-room-durable-object.ts";

export { PairRoom };

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

/**
 * A room that hands every note to one lane, whose sender is a script kept in storage: each call
 * takes the next outcome ("throw" fails the way a network error would) and is recorded.
 */
export class LaneRoom extends PairRoom {
  protected override deliveryLanes = ["AlertPush"];

  protected override laneSender = {
    send: async (entry: { noteId: string; lane: string; attempts: number }) => {
      const calls = (await this.ctx.storage.get<unknown[]>("laneCalls")) ?? [];
      await this.ctx.storage.put("laneCalls", [...calls, entry]);
      const script = (await this.ctx.storage.get<string[]>("laneScript")) ?? [];
      const next = script.shift() ?? "Delivered";
      await this.ctx.storage.put("laneScript", script);
      if (next === "throw") throw new Error("apns is down");
      return next as "Delivered" | "Retry" | "Abandon";
    },
  };
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
