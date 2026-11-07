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

// What a user should be told about the end of their pair: a row per user, written when their
// partner deletes their account. The app shows it while the user is unpaired.
export const partnerNotices = sqliteTable("partner_notices", {
  userId: text("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  reason: text("reason").notNull(),
  at: integer("at").notNull(),
});

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

// Who blocked whom. A block ends the pair and keeps the two from claiming each other's invites.
// Not foreign keys: the rows go with either user in the account erasure.
export const blocks = sqliteTable(
  "blocks",
  {
    blockerId: text("blocker_id").notNull(),
    blockedId: text("blocked_id").notNull(),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.blockerId, table.blockedId] }),
    index("blocks_blocked_id_index").on(table.blockedId),
  ],
);

// What a user keeps when their pair ends: purchases are never deleted. The coins are their share
// of the pair's balance, the rows of `kept_items` the inks and room pieces; a new pair's room is
// given them when the user pairs again, and the rows go. Not foreign keys: the account erasure
// deletes them.
export const keptWallets = sqliteTable("kept_wallets", {
  userId: text("user_id").primaryKey(),
  coins: integer("coins").notNull(),
});

export const keptItems = sqliteTable(
  "kept_items",
  {
    userId: text("user_id").notNull(),
    kind: text("kind").notNull(),
    itemId: text("item_id").notNull(),
  },
  (table) => [primaryKey({ columns: [table.userId, table.kind, table.itemId] })],
);

// What a user told the team about their partner. Kept after the pair or either account ends, so a
// report can still be acted on; the pair id is not a foreign key for the same reason.
export const partnerReports = sqliteTable(
  "partner_reports",
  {
    id: text("id").primaryKey(),
    reporterId: text("reporter_id").notNull(),
    reportedId: text("reported_id").notNull(),
    pairId: text("pair_id").notNull(),
    reason: text("reason").notNull(),
    details: text("details"),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [index("partner_reports_reported_id_index").on(table.reportedId)],
);

// The dev stage's demo partners: a bot user per owner, which pairs like anyone else but has no
// device and never signs in. Deleting either user takes the row with it.
export const demoPartners = sqliteTable("demo_partners", {
  botId: text("bot_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  ownerId: text("owner_id")
    .notNull()
    .unique()
    .references(() => users.id, { onDelete: "cascade" }),
  createdAt: integer("created_at").notNull(),
});

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
    // The build (`1.2.0+14`) and system (`iOS 26.1`) the app sent with its latest report that day,
    // as `clientInfoOf` reads the headers. Null for names the server records itself. The same
    // values Analytics Engine gets; here so the admin can split cohorts by build past its 90 days.
    appVersion: text("app_version"),
    os: text("os"),
  },
  (table) => [
    primaryKey({ columns: [table.pairId, table.userId, table.name, table.day] }),
    index("pair_events_day_index").on(table.day),
  ],
);

// What the detailed app events carried, per UTC day: how many times each name came with each
// detail (a catalogue id such as a cat or an item, or a word from a closed list), and the sum of
// their values (a price in coins). No user and no pair: only which things are chosen, for the
// admin's top lists. The rules for each name are `clientEventRules` in `contracts-domain/metrics`.
export const eventDetails = sqliteTable(
  "event_details",
  {
    name: text("name").notNull(),
    detail: text("detail").notNull(),
    day: text("day").notNull(),
    count: integer("count").notNull(),
    total: integer("total").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.name, table.detail, table.day] }),
    index("event_details_day_index").on(table.day),
  ],
);

// Funnels the owner saved in the admin panel: a name and the definition (steps, window, unit) as
// JSON, with who saved it (the Cloudflare Access email). Nothing about any pair or person.
export const adminFunnels = sqliteTable("admin_funnels", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  definition: text("definition").notNull(),
  createdAt: integer("created_at").notNull(),
  createdBy: text("created_by").notNull(),
});

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

// App Store purchases of coin packs (and the dev stage's mock ones), one row per original
// transaction, so each is credited once. `owner_id` is the pair the coins went to, or
// `demo:<code>` for a demo room on the dev stage; not a foreign key, so the record outlives the
// pair. No user, Apple account or receipt is kept. `flagged` is 1 when a refund could not take the
// whole pack back, for the admin to look at.
export const purchases = sqliteTable(
  "purchases",
  {
    originalTransactionId: text("original_transaction_id").primaryKey(),
    transactionId: text("transaction_id").notNull(),
    ownerId: text("owner_id").notNull(),
    productId: text("product_id").notNull(),
    coins: integer("coins").notNull(),
    environment: text("environment").notNull(),
    status: text("status").notNull(),
    refunds: integer("refunds").notNull(),
    flagged: integer("flagged").notNull(),
    purchasedAt: integer("purchased_at").notNull(),
    createdAt: integer("created_at").notNull(),
    updatedAt: integer("updated_at").notNull(),
  },
  (table) => [index("purchases_owner_id_index").on(table.ownerId)],
);

// Every change to an owner's bought coins; the balance is the sum of `amount`. Ids are stable
// (`purchase:<id>`, `refund:<id>`, `restore:<id>`), and the app merges entries by them.
export const coinLedger = sqliteTable(
  "coin_ledger",
  {
    id: text("id").primaryKey(),
    ownerId: text("owner_id").notNull(),
    kind: text("kind").notNull(),
    amount: integer("amount").notNull(),
    productId: text("product_id").notNull(),
    originalTransactionId: text("original_transaction_id").notNull(),
    at: integer("at").notNull(),
  },
  (table) => [index("coin_ledger_owner_id_index").on(table.ownerId, table.at)],
);

// The App Store Server Notifications handled, by Apple's UUID, so a retried one is applied once.
export const appStoreNotifications = sqliteTable(
  "app_store_notifications",
  {
    notificationUuid: text("notification_uuid").primaryKey(),
    type: text("type").notNull(),
    subtype: text("subtype"),
    environment: text("environment"),
    originalTransactionId: text("original_transaction_id"),
    outcome: text("outcome").notNull(),
    receivedAt: integer("received_at").notNull(),
  },
  (table) => [index("app_store_notifications_received_at_index").on(table.receivedAt)],
);

// One row per account and onboarding step: the answer, or a skip (`kind` = `Skipped`). Picks are a
// JSON array of option ids, so the admin panel counts them without reading `text`, the one column
// a person typed. A save keeps the row with the later `answered_at`. Deleted with the account.
export const onboardingAnswers = sqliteTable(
  "onboarding_answers",
  {
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    stepId: text("step_id").notNull(),
    version: text("version").notNull(),
    kind: text("kind").notNull(),
    optionIds: text("option_ids"),
    value: integer("value"),
    text: text("text"),
    answeredAt: integer("answered_at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.stepId] }),
    index("onboarding_answers_step_index").on(table.stepId),
  ],
);
