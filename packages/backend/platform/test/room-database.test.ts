import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { Effect, Schema, type Scope } from "effect";
import { describe, expect, it } from "vitest";
import { PlatformProbe } from "../src/platform-probe.ts";
import { openRoomDatabase } from "../src/room-database.ts";
import { roomProbe } from "../src/room-schema.ts";

const room = (name: string) => env.PAIR_ROOM.get(env.PAIR_ROOM.idFromName(name));

const tables = (storage: DurableObjectStorage) =>
  storage.sql
    .exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table'")
    .toArray()
    .map(({ name }) => name);

const history = (storage: DurableObjectStorage) =>
  storage.sql.exec("SELECT name FROM __drizzle_migrations").toArray();

const run = <A, E>(effect: Effect.Effect<A, E, Scope.Scope>) =>
  Effect.runPromise(Effect.scoped(effect));

describe("PairRoom migrations", () => {
  it("are applied on activation, before any request", async () => {
    await runInDurableObject(room("fresh"), (_, state) => {
      expect(tables(state.storage)).toContain("room_probe");
      expect(history(state.storage)).toHaveLength(1);
    });
  });

  it("re-apply as a no-op and keep the data", async () => {
    await runInDurableObject(room("again"), async (_, state) => {
      const before = history(state.storage);
      const row = { id: "a", createdAt: 1 };
      const rows = await run(
        Effect.gen(function* () {
          const db = yield* openRoomDatabase(state.storage);
          yield* db.insert(roomProbe).values(row);
          const reopened = yield* openRoomDatabase(state.storage);
          return yield* reopened.select().from(roomProbe);
        }),
      );
      expect(rows.map((found) => Schema.decodeUnknownSync(PlatformProbe)(found))).toEqual([row]);
      expect(history(state.storage)).toEqual(before);
    });
  });

  it("roll back as a whole when one cannot apply, and apply once it is fixed", async () => {
    await runInDurableObject(room("rollback"), async (_, state) => {
      const before = tables(state.storage);
      const broken = {
        "20300101000000_good": "CREATE TABLE later (id TEXT PRIMARY KEY);",
        "20300101000001_bad": "CREATE TABLE ;",
      };
      await expect(run(openRoomDatabase(state.storage, { migrations: broken }))).rejects.toThrow();
      expect(tables(state.storage)).toEqual(before);

      const fixed = {
        "20300101000000_good": broken["20300101000000_good"],
        "20300101000001_bad": "CREATE TABLE fixed (id TEXT PRIMARY KEY);",
      };
      await run(openRoomDatabase(state.storage, { migrations: fixed }));
      expect(tables(state.storage)).toEqual(expect.arrayContaining(["later", "fixed"]));
    });
  });

  it("fail every request to an object that cannot migrate, and each one retries", async () => {
    const stub = env.BROKEN_ROOM.get(env.BROKEN_ROOM.idFromName("broken"));
    await expect(stub.fetch("https://room/")).rejects.toThrow();
    await expect(stub.fetch("https://room/")).rejects.toThrow();
  });
});
