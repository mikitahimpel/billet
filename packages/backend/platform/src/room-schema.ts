import {
  check,
  index,
  integer,
  primaryKey,
  real,
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

// The couple's cat, once adopted: its profile and temper, and the last journal entry's `seq` and
// time. The row exists only after adoption.
export const cat = sqliteTable(
  "cat",
  {
    id: integer("id").primaryKey(),
    name: text("name").notNull(),
    model: text("model").notNull(),
    coat: text("coat").notNull(),
    bornAt: integer("born_at").notNull(),
    natureSeed: text("nature_seed").notNull(),
    utcOffsetSeconds: integer("utc_offset_seconds").notNull(),
    curious: real("curious").notNull(),
    lazy: real("lazy").notNull(),
    cuddly: real("cuddly").notNull(),
    lastSeq: integer("last_seq").notNull(),
    lastAt: integer("last_at"),
  },
  (table) => [check("cat_single_row", sql`${table.id} = 1`)],
);

// The cat's journal: `body` is the `CatEvent` as JSON. `id` is the phone's UUID, one entry each;
// `at` is indexed for the needs fold, which reads the last week.
export const catEntry = sqliteTable(
  "cat_entry",
  {
    seq: integer("seq").primaryKey(),
    id: text("id").notNull(),
    by: text("by").notNull(),
    at: integer("at").notNull(),
    body: text("body").notNull(),
  },
  (table) => [uniqueIndex("cat_entry_id").on(table.id), index("cat_entry_at").on(table.at)],
);

// The Inbox: one row per item, keyed by its source's id. `sortKey` is the item's cursor, so a
// page is a range on one index. `doerUser` is null for the cat and the store; `body` holds the
// event and the target as JSON.
export const activity = sqliteTable(
  "activity",
  {
    id: text("id").primaryKey(),
    sortKey: text("sort_key").notNull(),
    at: integer("at").notNull(),
    doerKind: text("doer_kind").notNull(),
    doerUser: text("doer_user"),
    body: text("body").notNull(),
  },
  (table) => [index("activity_sort_key").on(table.sortKey), index("activity_at").on(table.at)],
);

// Each member's read mark: the cursor of the newest item they have read.
export const activityRead = sqliteTable("activity_read", {
  user: text("user").primaryKey(),
  upTo: text("up_to").notNull(),
});

// The ink colours the pair has bought, in the order it got them (`position`). The free ink is
// every pair's and has no row. Pairing again opens a new room, which starts with the free ink only.
export const ownedInk = sqliteTable("owned_ink", {
  inkId: text("ink_id").primaryKey(),
  position: integer("position").notNull(),
});
