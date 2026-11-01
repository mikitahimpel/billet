import { DurableObject } from "cloudflare:workers";
import { Effect } from "effect";
import { openRoomDatabase } from "../src/room-database.ts";

import type { RoomMigrations } from "../src/room-database.ts";

// The Worker under test: exports the object class, as apps/api/src/worker.ts does.
import { DemoRoom } from "../src/demo-room-durable-object.ts";

export { DemoRoom };

/** DemoRoom with a throwaway APNs key and a recording transport, so no request leaves the test. */
export class StubbedDemoRoom extends DemoRoom {
  protected override async apnsCredentials() {
    const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
      "sign",
    ])) as CryptoKeyPair;
    const der = new Uint8Array(
      (await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer,
    );
    const body = btoa(String.fromCharCode(...der));
    return {
      key: `-----BEGIN PRIVATE KEY-----
${body}
-----END PRIVATE KEY-----`,
      keyId: "TESTKEYID1",
    };
  }

  protected override apnsFetch = async (url: string, init: RequestInit) => {
    const calls = (await this.ctx.storage.get<unknown[]>("apnsCalls")) ?? [];
    const headers = Object.fromEntries(new Headers(init.headers).entries());
    await this.ctx.storage.put("apnsCalls", [...calls, { url, headers, body: String(init.body) }]);
    return new Response(null, { status: 200 });
  };
}

/** DemoRoom whose APNs request never completes, to prove an ack does not wait on it. */
export class HangingApnsRoom extends StubbedDemoRoom {
  protected override apnsFetch = (): Promise<Response> => new Promise(() => {});
}

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
  fetch: () => new Response(null, { status: 404 }),
};
