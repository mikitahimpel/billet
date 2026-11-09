import { DurableObject } from "cloudflare:workers";
import { Effect } from "effect";
import { respondApi } from "../src/api-fetch.ts";
import type { WorkerEnv } from "../src/worker-env.ts";
import { openRoomDatabase } from "../src/room-database.ts";

import { testExperiments } from "./test-experiments.ts";
import type { RoomMigrations } from "../src/room-database.ts";

// The Worker under test: exports the object class, as apps/api/src/worker.ts does.
import { PairRoom as LivePairRoom } from "../src/pair-room-durable-object.ts";
import { testNowOf } from "./test-now.ts";

/**
 * `advanceClock` moves the test instant on in memory, so an eviction takes it back.
 */
export class PairRoom extends LivePairRoom {
  private advancedMs = 0;

  advanceClock(ms: number): void {
    this.advancedMs += ms;
  }

  protected override clock(): number {
    return testNowOf(this.env as { readonly TEST_NOW?: string }) + this.advancedMs;
  }
}

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
 * Each send takes the next scripted outcome from storage; "throw" fails like a network error.
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

export default {
  // The gate and the rate limit read TEST_NOW, so a test's requests share one rate-limit window
  // instead of straddling a minute boundary of the real clock. Better Auth still reads the real one.
  fetch: (request: Request, env: WorkerEnv, ctx: ExecutionContext) =>
    respondApi(request, env, ctx, testExperiments, () =>
      testNowOf(env as { readonly TEST_NOW?: string }),
    ),
};
