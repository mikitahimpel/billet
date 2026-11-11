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
    streakBest: integer("streak_best").notNull().default(0),
    // The pair's local days, YYYY-MM-DD: the last one that counted, and the last restore.
    streakLastDay: text("streak_last_day"),
    streakRestoredOn: text("streak_restored_on"),
    // The days after the last lit one that only one partner did yet: `StreakMark`s as JSON.
    streakMarks: text("streak_marks"),
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

// One row per note and lane; the rules are in the pair-room package's `delivery-ledger.ts`.
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

// One row, only after adoption.
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

// `sortKey` is the item's cursor, so a page is a range on one index. `doerUser` is null for the
// cat and the store.
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

// The free ink is every pair's and has no row.
export const ownedInk = sqliteTable("owned_ink", {
  inkId: text("ink_id").primaryKey(),
  position: integer("position").notNull(),
});

// The starter pieces are every pair's and have no row.
export const ownedItem = sqliteTable("owned_item", {
  itemId: text("item_id").primaryKey(),
  position: integer("position").notNull(),
});

// Written whole on every commit, so a piece taken off leaves no row.
export const wish = sqliteTable("wish", {
  itemId: text("item_id").primaryKey(),
  position: integer("position").notNull(),
});

// Where each piece stands, written whole on every commit like the wishlist. `position` keeps the order.
export const placement = sqliteTable("placement", {
  itemId: text("item_id").primaryKey(),
  surface: text("surface").notNull(),
  u: integer("u").notNull(),
  v: integer("v").notNull(),
  quarterTurns: integer("quarter_turns").notNull(),
  position: integer("position").notNull(),
});

// The room's own furniture the pair put away. A piece of it with no placement and no row here stands at home.
export const stowedPiece = sqliteTable("stowed_piece", {
  itemId: text("item_id").primaryKey(),
  position: integer("position").notNull(),
});

// The newest layout changes applied, oldest first, so a repeated change is answered and not applied twice.
export const layoutLog = sqliteTable("layout_log", {
  changeId: text("change_id").primaryKey(),
  position: integer("position").notNull(),
});

// `day` is the cat's local day the daily caps count against. No row means no coin yet.
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

export const claimedBonus = sqliteTable("claimed_bonus", {
  collectionId: text("collection_id").primaryKey(),
  position: integer("position").notNull(),
});

// One row per member: a new check-in writes over it.
export const mood = sqliteTable("mood", {
  user: text("user").primaryKey(),
  mood: text("mood").notNull(),
  note: text("note"),
  at: integer("at").notNull(),
});

// `id` is `<kind>:<source>`, unique, so a repeated earn or buy cannot pay or charge twice.
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

// `body` is the JSON of `Loves`.
export const giftLoves = sqliteTable("gift_loves", {
  user: text("user").primaryKey(),
  body: text("body").notNull(),
});

// Both partners read and change every row; `icon_symbol` and `icon_tint` are the list's tile.
export const lists = sqliteTable("lists", {
  id: text("id").primaryKey(),
  position: integer("position").notNull(),
  kind: text("kind").notNull(),
  title: text("title").notNull(),
  iconSymbol: text("icon_symbol").notNull(),
  iconTint: text("icon_tint").notNull(),
});

// `done_by` and `done_at` are set once ticked. `media_*` name a TMDB film or show; `wants` is a
// JSON array of members. `place`, `visited_in` (a month, `2026-10`) and `moments` (JSON moment
// ids) are for travel.
export const listItems = sqliteTable(
  "list_items",
  {
    id: text("id").primaryKey(),
    listId: text("list_id").notNull(),
    position: integer("position").notNull(),
    text: text("text").notNull(),
    author: text("author").notNull(),
    addedAt: integer("added_at").notNull(),
    doneBy: text("done_by"),
    doneAt: integer("done_at"),
    quantity: text("quantity"),
    note: text("note"),
    icon: text("icon"),
    aisle: text("aisle"),
    mediaKind: text("media_kind"),
    mediaTmdb: integer("media_tmdb"),
    mediaYear: integer("media_year"),
    mediaPoster: text("media_poster"),
    country: text("country"),
    place: integer("place", { mode: "boolean" }),
    visitedIn: text("visited_in"),
    moments: text("moments"),
    wants: text("wants").notNull(),
  },
  (table) => [index("list_items_list").on(table.listId, table.position)],
);

// The key of each list change the room applied, so a retry applies nothing. Kept 30 days behind
// the newest, like the Inbox.
export const listKeys = sqliteTable(
  "list_keys",
  {
    key: text("key").primaryKey(),
    at: integer("at").notNull(),
  },
  (table) => [index("list_keys_at").on(table.at)],
);

// Pick tonight: each member's latest swipe on each card, `title` being `item:<id>`, `movie:<tmdb>`
// or `tv:<tmdb>`. `name` and `poster_path` are the card's, for the match it may make. Rows older
// than a session (24 hours) are deleted on the next swipe.
export const movieSwipes = sqliteTable(
  "movie_swipes",
  {
    member: text("member").notNull(),
    title: text("title").notNull(),
    choice: text("choice").notNull(),
    name: text("name").notNull(),
    posterPath: text("poster_path"),
    at: integer("at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.member, table.title] }),
    index("movie_swipes_at").on(table.at),
  ],
);

// `day` is the cat's local day, as for coins. Kept for good: a pair's next questions follow every
// round it had.
export const guessRounds = sqliteTable("guess_rounds", {
  day: text("day").primaryKey(),
  subject: text("subject").notNull(),
  questions: text("questions").notNull(),
});

// Each member's locked answer to each question of a round: `option` is 0 to 3. One row each, so a
// second answer cannot replace the first.
export const guessAnswers = sqliteTable(
  "guess_answers",
  {
    day: text("day").notNull(),
    member: text("member").notNull(),
    question: integer("question").notNull(),
    option: integer("option").notNull(),
    at: integer("at").notNull(),
  },
  (table) => [primaryKey({ columns: [table.day, table.member, table.question] })],
);

// Each member's Who knows who points per week, `week` being its Monday. Added to when a round
// reveals; the all-time score and the best week are read from these rows.
export const guessWeeks = sqliteTable(
  "guess_weeks",
  {
    week: text("week").notNull(),
    member: text("member").notNull(),
    points: integer("points").notNull(),
  },
  (table) => [primaryKey({ columns: [table.week, table.member] })],
);

// Draw-guess riddles, each a `RiddleRow` as JSON in `body`, word included: the room decides what
// each member may see. `drawer` and `ended_at` (null while open) are kept beside it for the reads
// that pick the open riddles and the latest ended ones.
export const riddles = sqliteTable(
  "riddles",
  {
    id: text("id").primaryKey(),
    drawer: text("drawer").notNull(),
    endedAt: integer("ended_at"),
    body: text("body").notNull(),
  },
  (table) => [index("riddles_ended_at").on(table.endedAt)],
);

// Every try at a riddle under the guesser's key, so a retried try answers as the first did.
export const riddleGuesses = sqliteTable(
  "riddle_guesses",
  {
    riddle: text("riddle").notNull(),
    key: text("key").notNull(),
    right: integer("right", { mode: "boolean" }).notNull(),
    at: integer("at").notNull(),
  },
  (table) => [primaryKey({ columns: [table.riddle, table.key] })],
);

// The pair's draw-guess series: solves in a row since the last give-up, and the best run. One row.
export const riddleSeries = sqliteTable(
  "riddle_series",
  {
    id: integer("id").primaryKey(),
    series: integer("series").notNull(),
    best: integer("best").notNull(),
  },
  (table) => [check("riddle_series_single_row", sql`${table.id} = 1`)],
);
