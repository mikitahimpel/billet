import {
  check,
  integer,
  primaryKey,
  sqliteTable,
  text,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";
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

// A committed note: `body` is the `Note` as JSON. `author` and `idempotencyKey` let a repeated send
// find its note; both are null on notes stored before keys existed, which no send can repeat.
export const note = sqliteTable(
  "note",
  {
    seq: integer("seq").primaryKey(),
    body: text("body").notNull(),
    author: text("author"),
    idempotencyKey: text("idempotency_key"),
  },
  (table) => [uniqueIndex("note_author_key").on(table.author, table.idempotencyKey)],
);

// One row per note and delivery lane: how far that delivery got. The alarm works through the
// pending ones. See `delivery-ledger.ts` in the pair-room package for the rules.
export const delivery = sqliteTable(
  "delivery",
  {
    noteId: text("note_id").notNull(),
    lane: text("lane").notNull(),
    status: text("status").notNull(),
    attempts: integer("attempts").notNull(),
    nextAttemptAt: integer("next_attempt_at").notNull(),
  },
  (table) => [primaryKey({ columns: [table.noteId, table.lane] })],
);

// The ink colours the pair has bought, in the order it got them (`position`). The free ink is
// every pair's and has no row. Pairing again opens a new room, which starts with the free ink only.
export const ownedInk = sqliteTable("owned_ink", {
  inkId: text("ink_id").primaryKey(),
  position: integer("position").notNull(),
});
