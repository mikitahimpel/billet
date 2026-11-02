import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { Effect, Layer, Schema, type Scope } from "effect";
import { describe, expect, it } from "vitest";
import { openRoomDatabase } from "../src/room-database.ts";
import * as roomSchema from "../src/room-schema.ts";
import { Note } from "@billet/contracts-domain/note";
import { RoomStore } from "@billet/backend-pair-room/room-store";
import { RoomDb, SqliteRoomStore } from "../src/pair-room-sqlite-store.ts";
import { StoredNote } from "../src/room-rows.ts";
import { note } from "../src/room-schema.ts";
import {
  appliedColumns,
  declaredColumns,
  getTableName,
  isBookkeeping,
  tablesOf,
} from "./table-columns.ts";

const room = (name: string) => env.ACTIVATED_ROOM.get(env.ACTIVATED_ROOM.idFromName(name));

const tables = (storage: DurableObjectStorage) =>
  storage.sql
    .exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table'")
    .toArray()
    .map(({ name }) => name);

const userTables = (storage: DurableObjectStorage) =>
  tables(storage).filter((name) => !isBookkeeping(name));

const history = (storage: DurableObjectStorage) =>
  storage.sql.exec("SELECT name FROM __drizzle_migrations").toArray();

const run = <A, E>(effect: Effect.Effect<A, E, Scope.Scope>) =>
  Effect.runPromise(Effect.scoped(effect));

describe("room migrations", () => {
  it("are applied on activation, before any request", async () => {
    await runInDurableObject(room("fresh"), (_, state) => {
      expect(tables(state.storage)).toEqual(expect.arrayContaining(["room", "note"]));
      expect(tables(state.storage)).not.toContain("room_probe");
      expect(history(state.storage)).toHaveLength(4);
    });
  });

  it("leave the tables and columns the Drizzle schema declares, and no others", async () => {
    await runInDurableObject(room("columns"), (_, state) => {
      const tables = tablesOf(roomSchema);
      expect(tables.length).toBeGreaterThan(0);
      expect(userTables(state.storage).toSorted()).toEqual(tables.map(getTableName).toSorted());
      for (const table of tables) {
        const info = state.storage.sql
          .exec<{ name: string; type: string; notnull: number; pk: number }>(
            `PRAGMA table_info(${getTableName(table)})`,
          )
          .toArray();
        expect(appliedColumns(info)).toEqual(declaredColumns(table));
      }
    });
  });

  it("re-apply as a no-op and keep the data", async () => {
    await runInDurableObject(room("again"), async (_, state) => {
      const before = history(state.storage);
      const row = { seq: 1, body: "{}", author: null, idempotencyKey: null };
      const rows = await run(
        Effect.gen(function* () {
          const db = yield* openRoomDatabase(state.storage);
          yield* db.insert(note).values(row);
          const reopened = yield* openRoomDatabase(state.storage);
          return yield* reopened.select().from(note);
        }),
      );
      expect(rows.map((found) => Schema.decodeUnknownSync(StoredNote)(found))).toEqual([row]);
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

  it("adopts a room made by the raw-SQL store, with its rows, and drops the old bookkeeping", async () => {
    const legacy = env.LEGACY_ROOM.get(env.LEGACY_ROOM.idFromName("legacy"));
    const photo = Schema.decodeUnknownSync(Note)({
      _tag: "Photo",
      id: "note-1",
      author: "user-alice",
      sentAt: 1_700_000_000_000,
      image: "pairs/pair-1/notes/n.png",
    });
    await runInDurableObject(legacy, async (_, state) => {
      state.storage.sql.exec(
        `CREATE TABLE room (
           id INTEGER PRIMARY KEY CHECK (id = 1),
           pair_id TEXT NOT NULL,
           first_user TEXT NOT NULL,
           first_presence TEXT NOT NULL,
           second_user TEXT NOT NULL,
           second_presence TEXT NOT NULL,
           last_seq INTEGER NOT NULL,
           streak_days INTEGER NOT NULL
         );
         CREATE TABLE note (seq INTEGER PRIMARY KEY, body TEXT NOT NULL);
         CREATE TABLE migration (version INTEGER PRIMARY KEY);
         INSERT INTO migration (version) VALUES (1);`,
      );
      state.storage.sql.exec(
        "INSERT INTO room VALUES (1, 'pair-1', 'user-alice', 'idle', 'user-bob', 'drawing', 1, 4)",
      );
      state.storage.sql.exec(
        "INSERT INTO note (seq, body) VALUES (1, ?)",
        Schema.encodeSync(Schema.fromJsonString(Note))(photo),
      );

      const { state: loaded, notes } = await run(
        Effect.gen(function* () {
          const db = yield* openRoomDatabase(state.storage);
          const store = yield* RoomStore.pipe(
            Effect.provide(SqliteRoomStore.pipe(Layer.provide(Layer.succeed(RoomDb, db)))),
          );
          return { state: yield* store.load, notes: yield* store.notesAfter(0, 10) };
        }),
      );

      expect(loaded).toMatchObject({
        _tag: "Active",
        pairId: "pair-1",
        lastSeq: 1,
        streakDays: 4,
        members: [
          { user: "user-alice", presence: "idle" },
          { user: "user-bob", presence: "drawing" },
        ],
      });
      expect(notes).toEqual([{ seq: 1, note: photo }]);
      expect(userTables(state.storage).toSorted()).toEqual(["delivery", "note", "room"]);
      expect(history(state.storage)).toHaveLength(4);
    });
  });
});
