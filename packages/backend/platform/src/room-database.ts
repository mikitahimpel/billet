import * as SqliteClient from "@effect/sql-sqlite-do/SqliteClient";
import { makeWithDefaults } from "drizzle-orm/effect-sqlite-do";
import { migrate } from "drizzle-orm/effect-sqlite-do/migrator";
import { Effect, Layer } from "effect";
import roomMigrations from "../migrations/room/migrations.js";

/** The `migrations.js` that `drizzle-kit generate --driver durable-sqlite` writes. */
export interface RoomMigrations {
  readonly migrations: Record<string, string>;
}

/**
 * A failed migration is a defect: run inside `blockConcurrencyWhile`, which resets and retries.
 */
export const openRoomDatabase = (
  storage: DurableObjectStorage,
  migrations: RoomMigrations = roomMigrations,
) =>
  Effect.gen(function* () {
    const services = yield* Layer.build(SqliteClient.layer({ storage }));
    const db = yield* makeWithDefaults({ storage }).pipe(Effect.provideContext(services));
    yield* migrate(db, { migrations: migrations.migrations });
    return db;
  }).pipe(Effect.orDie);

export type RoomDatabase = Effect.Success<ReturnType<typeof openRoomDatabase>>;
