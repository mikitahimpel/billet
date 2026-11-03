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

// Everything else points at this table. `auth_user` holds the same ids for Better Auth, which owns
// sign-in, and a hook in better-auth-engine.ts writes the row here when it opens a user.
export const users = sqliteTable("users", {
  id: text("id").primaryKey(),
  createdAt: integer("created_at").notNull(),
});

// Better Auth's own tables (better-auth-engine.ts names each column). It writes dates as ISO text
// and booleans as 0 or 1, unlike the epoch milliseconds everywhere else. No email is real: an
// anonymous user's is made up, and an Apple user's is built from their subject, never Apple's.
export const authUsers = sqliteTable(
  "auth_user",
  {
    id: text("id").primaryKey(),
    name: text("name").notNull(),
    email: text("email").notNull(),
    emailVerified: integer("email_verified").notNull(),
    image: text("image"),
    isAnonymous: integer("is_anonymous"),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (table) => [uniqueIndex("auth_user_email_unique").on(table.email)],
);

// `token` is SHA-256 of the session token, which is never stored (hashed-session-tokens.ts). Each
// session has its own device, and push tokens hang off the device.
export const authSessions = sqliteTable(
  "auth_session",
  {
    id: text("id").primaryKey(),
    token: text("token").notNull(),
    userId: text("user_id")
      .notNull()
      .references(() => authUsers.id, { onDelete: "cascade" }),
    deviceId: text("device_id")
      .notNull()
      .references(() => devices.id, { onDelete: "cascade" }),
    expiresAt: text("expires_at").notNull(),
    ipAddress: text("ip_address"),
    userAgent: text("user_agent"),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (table) => [
    uniqueIndex("auth_session_token_unique").on(table.token),
    uniqueIndex("auth_session_device_id_unique").on(table.deviceId),
    index("auth_session_user_id_index").on(table.userId),
    index("auth_session_expires_at_index").on(table.expiresAt),
  ],
);

// Linked identities: `provider_id` is `apple` and `account_id` the Apple subject. One Apple ID
// belongs to one user, which the unique index makes a database rule. No Apple token is kept.
export const authAccounts = sqliteTable(
  "auth_account",
  {
    id: text("id").primaryKey(),
    accountId: text("account_id").notNull(),
    providerId: text("provider_id").notNull(),
    userId: text("user_id")
      .notNull()
      .references(() => authUsers.id, { onDelete: "cascade" }),
    accessToken: text("access_token"),
    refreshToken: text("refresh_token"),
    idToken: text("id_token"),
    accessTokenExpiresAt: text("access_token_expires_at"),
    refreshTokenExpiresAt: text("refresh_token_expires_at"),
    scope: text("scope"),
    password: text("password"),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (table) => [
    uniqueIndex("auth_account_provider_account_unique").on(table.providerId, table.accountId),
    index("auth_account_user_id_index").on(table.userId),
  ],
);

// Better Auth's one-time values. None of the flows in use writes here today; it must exist.
export const authVerifications = sqliteTable(
  "auth_verification",
  {
    id: text("id").primaryKey(),
    identifier: text("identifier").notNull(),
    value: text("value").notNull(),
    expiresAt: text("expires_at").notNull(),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (table) => [index("auth_verification_identifier_index").on(table.identifier)],
);

// `key_hash` is SHA-256 of the account key, which is never stored. The key is the anonymous
// account: the app keeps it in the iCloud Keychain and signs in with it on every phone.
export const accountKeys = sqliteTable(
  "account_keys",
  {
    keyHash: text("key_hash").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [index("account_keys_user_id_index").on(table.userId)],
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

// The variant each pair was given in each experiment it entered. Only pairs inside an experiment
// have a row, and a row is never updated, so changing weights or exposure later moves nobody.
// Pairs outside it get the default and have no row. The pair id is not a foreign key: a pair has no
// table of its own, and the rows stay for analysis after the pair ends.
export const pairFlags = sqliteTable(
  "pair_flags",
  {
    pairId: text("pair_id").notNull(),
    experimentKey: text("experiment_key").notNull(),
    variant: text("variant").notNull(),
    assignedAt: integer("assigned_at").notNull(),
  },
  (table) => [primaryKey({ columns: [table.pairId, table.experimentKey] })],
);

// First-party counts: how many times one person did one named thing on one UTC day, with the pair
// they were in at the time (empty before pairing). Nothing else is stored: no note, image or
// text, no device, address or place. The names are a closed list in `contracts-domain/metrics`.
// Like `pair_flags`, the pair id is not a foreign key and the rows outlive the pair for analysis.
export const pairEvents = sqliteTable(
  "pair_events",
  {
    pairId: text("pair_id").notNull(),
    userId: text("user_id").notNull(),
    name: text("name").notNull(),
    day: text("day").notNull(),
    count: integer("count").notNull(),
    firstAt: integer("first_at").notNull(),
    lastAt: integer("last_at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.pairId, table.userId, table.name, table.day] }),
    index("pair_events_day_index").on(table.day),
  ],
);

// The live configuration of each experiment and remote flag, as the admin panel last saved it.
// The registry in `backend-flags/experiments` defines the keys and variants; a row here only
// changes weights, default, exposure, status, kill switch and targeting (JSON in `config`).
// `version` goes up by one per save, so two editors cannot overwrite each other.
export const flagConfigs = sqliteTable("flag_configs", {
  key: text("key").primaryKey(),
  config: text("config").notNull(),
  version: integer("version").notNull(),
  updatedAt: integer("updated_at").notNull(),
  updatedBy: text("updated_by").notNull(),
});

// Every change the admin panel made, newest last: who (the Cloudflare Access email), what, and the
// configuration before and after. Written in the same batch as the change itself.
export const flagChanges = sqliteTable(
  "flag_changes",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    key: text("key").notNull(),
    at: integer("at").notNull(),
    by: text("by").notNull(),
    action: text("action").notNull(),
    pairId: text("pair_id"),
    before: text("before"),
    after: text("after"),
  },
  (table) => [index("flag_changes_key_index").on(table.key, table.id)],
);

// A variant forced on one pair, for testing on the owner's own phones. It beats the pair's stored
// assignment but never the kill switch. Not a foreign key, like `pair_flags`.
export const pairFlagOverrides = sqliteTable(
  "pair_flag_overrides",
  {
    pairId: text("pair_id").notNull(),
    experimentKey: text("experiment_key").notNull(),
    variant: text("variant").notNull(),
    setAt: integer("set_at").notNull(),
    setBy: text("set_by").notNull(),
  },
  (table) => [primaryKey({ columns: [table.pairId, table.experimentKey] })],
);
