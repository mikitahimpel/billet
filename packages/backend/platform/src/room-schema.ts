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
    lastReactionRev: integer("last_reaction_rev"),
    // The pair's local day it last opened the daily gift on; null before the first.
    giftDay: text("gift_day"),
    // A room stored before the welcome coins reads false and gets them once.
    welcomed: integer("welcomed", { mode: "boolean" }).notNull().default(false),
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

// Each partner's latest reaction to each note, one row per pair of them. `reaction` is null once
// it was taken back, so the row still carries the change. `rev` orders the changes.
export const reaction = sqliteTable(
  "reaction",
  {
    noteId: text("note_id").notNull(),
    by: text("by").notNull(),
    reaction: text("reaction"),
    at: integer("at").notNull(),
    rev: integer("rev").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.noteId, table.by] }),
    uniqueIndex("reaction_rev").on(table.rev),
  ],
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

// The room's pieces the pair has bought, in the order it got them (`position`). The starter
// pieces are every pair's and have no row.
export const ownedItem = sqliteTable("owned_item", {
  itemId: text("item_id").primaryKey(),
  position: integer("position").notNull(),
});

// The pieces the pair wishes for, in the order they were wished (`position`). Written whole on
// every commit, so a piece taken off leaves no row.
export const wish = sqliteTable("wish", {
  itemId: text("item_id").primaryKey(),
  position: integer("position").notNull(),
});

// The pair's coins: the balance, and what care has earned on `day` (the cat's local day) against
// each daily cap. No row means no coin yet.
export const wallet = sqliteTable(
  "wallet",
  {
    id: integer("id").primaryKey(),
    balance: integer("balance").notNull(),
    day: text("day"),
    care: integer("care").notNull(),
    notes: integer("notes").notNull(),
    games: integer("games").notNull(),
    lists: integer("lists").notNull().default(0),
  },
  (table) => [check("wallet_single_row", sql`${table.id} = 1`)],
);

// The collections whose bonus the pair was paid, in the order it was paid (`position`).
export const claimedBonus = sqliteTable("claimed_bonus", {
  collectionId: text("collection_id").primaryKey(),
  position: integer("position").notNull(),
});

// The wallet's entries, in the order they were stored (`seq`). `id` is `<kind>:<source>`, one
// entry each, so a repeated earn or buy cannot pay or charge twice.
export const coinEntry = sqliteTable(
  "coin_entry",
  {
    seq: integer("seq").primaryKey({ autoIncrement: true }),
    id: text("id").notNull(),
    kind: text("kind").notNull(),
    amount: integer("amount").notNull(),
    ref: text("ref").notNull(),
    at: integer("at").notNull(),
  },
  (table) => [uniqueIndex("coin_entry_id").on(table.id)],
);

// A partner's gift wishes. Both partners read every row; who plans to gift one is in `gift_plan`.
export const giftWish = sqliteTable("gift_wish", {
  id: text("id").primaryKey(),
  owner: text("owner").notNull(),
  title: text("title").notNull(),
  link: text("link").notNull(),
  price: text("price").notNull(),
  note: text("note").notNull(),
  mostWanted: integer("most_wanted").notNull(),
  occasionTitle: text("occasion_title"),
  occasionDate: integer("occasion_date"),
  addedAt: integer("added_at").notNull(),
  receivedAt: integer("received_at"),
  giftedBy: text("gifted_by"),
});

// A giver's secret plan for one of the partner's wishes. Only the giver's own answers read it.
export const giftPlan = sqliteTable(
  "gift_plan",
  {
    wishId: text("wish_id").notNull(),
    giver: text("giver").notNull(),
    stage: text("stage").notNull(),
  },
  (table) => [primaryKey({ columns: [table.wishId, table.giver] })],
);

// Each partner's "What I love", as the JSON of `Loves`.
export const giftLoves = sqliteTable("gift_loves", {
  user: text("user").primaryKey(),
  body: text("body").notNull(),
});
