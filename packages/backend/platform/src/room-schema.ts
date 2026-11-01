import { check, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";
import { sql } from "drizzle-orm";

// Durable Object SQLite tables, one set per `PairRoom`. `pnpm db:generate` writes the migrations.

// The one row of the room: the pair, its two members with their presence, and the counters.
export const room = sqliteTable(
  "room",
  {
    id: integer("id").primaryKey(),
    pairId: text("pair_id").notNull(),
    firstUser: text("first_user").notNull(),
    firstPresence: text("first_presence").notNull(),
    secondUser: text("second_user").notNull(),
    secondPresence: text("second_presence").notNull(),
    lastSeq: integer("last_seq").notNull(),
    streakDays: integer("streak_days").notNull(),
  },
  (table) => [check("room_single_row", sql`${table.id} = 1`)],
);

// A committed note: `body` is the `Note` as JSON.
export const note = sqliteTable("note", {
  seq: integer("seq").primaryKey(),
  body: text("body").notNull(),
});
