import {
  index,
  integer,
  primaryKey,
  sqliteTable,
  text,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";

// D1 tables. `Drizzle.Schema` in the root alchemy.run.ts generates migrations from this file, so it
// imports nothing but drizzle-orm: drizzle-kit loads it in Node, outside the Worker.

export const users = sqliteTable(
  "users",
  {
    id: text("id").primaryKey(),
    appleSubject: text("apple_subject").notNull(),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [uniqueIndex("users_apple_subject_unique").on(table.appleSubject)],
);

export const devices = sqliteTable(
  "devices",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => users.id),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [index("devices_user_id_index").on(table.userId)],
);

// `token_hash` is SHA-256 of the session token, which is never stored. A device has one session and
// the session reaches its user through the device, so the two can't disagree.
export const sessions = sqliteTable(
  "sessions",
  {
    tokenHash: text("token_hash").primaryKey(),
    deviceId: text("device_id")
      .notNull()
      .references(() => devices.id, { onDelete: "cascade" }),
    createdAt: integer("created_at").notNull(),
    expiresAt: integer("expires_at").notNull(),
  },
  (table) => [
    uniqueIndex("sessions_device_id_unique").on(table.deviceId),
    index("sessions_expires_at_index").on(table.expiresAt),
  ],
);

// `nonce_hash` is SHA-256 of the nonce, which is never stored.
export const authChallenges = sqliteTable(
  "auth_challenges",
  {
    nonceHash: text("nonce_hash").primaryKey(),
    expiresAt: integer("expires_at").notNull(),
  },
  (table) => [index("auth_challenges_expires_at_index").on(table.expiresAt)],
);

// `code_hash` is SHA-256 of the invite code, which is never stored. A user has one invite at a time.
export const invites = sqliteTable(
  "invites",
  {
    codeHash: text("code_hash").primaryKey(),
    ownerId: text("owner_id")
      .notNull()
      .references(() => users.id),
    createdAt: integer("created_at").notNull(),
    expiresAt: integer("expires_at").notNull(),
  },
  (table) => [
    uniqueIndex("invites_owner_id_unique").on(table.ownerId),
    index("invites_expires_at_index").on(table.expiresAt),
  ],
);

// The pair lookup. Keying on the user is what makes one partner per account a database rule.
export const pairMembers = sqliteTable(
  "pair_members",
  {
    userId: text("user_id")
      .primaryKey()
      .references(() => users.id),
    pairId: text("pair_id").notNull(),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [index("pair_members_pair_id_index").on(table.pairId)],
);

export const pushTokens = sqliteTable(
  "push_tokens",
  {
    deviceId: text("device_id")
      .notNull()
      .references(() => devices.id, { onDelete: "cascade" }),
    kind: text("kind").notNull(),
    environment: text("environment").notNull(),
    token: text("token").notNull(),
    updatedAt: integer("updated_at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.deviceId, table.kind] }),
    uniqueIndex("push_tokens_token_kind_unique").on(table.token, table.kind),
  ],
);

// Fixed-window request counters. `bucket` is a SHA-256 of the route group and the caller's address,
// never the address itself. Old windows are deleted as new ones are written.
export const rateLimits = sqliteTable(
  "rate_limits",
  {
    bucket: text("bucket").notNull(),
    windowStart: integer("window_start").notNull(),
    count: integer("count").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.bucket, table.windowStart] }),
    index("rate_limits_window_start_index").on(table.windowStart),
  ],
);
