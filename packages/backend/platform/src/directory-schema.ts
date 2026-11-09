import {
  index,
  integer,
  primaryKey,
  real,
  sqliteTable,
  text,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";

// drizzle-kit loads this file in Node, outside the Worker, so it imports nothing but drizzle-orm.

// `auth_user` holds the same ids for Better Auth; a hook in better-auth-engine.ts writes this row.
export const users = sqliteTable("users", {
  id: text("id").primaryKey(),
  createdAt: integer("created_at").notNull(),
});

// Better Auth writes dates as ISO text and booleans as 0 or 1, unlike epoch milliseconds elsewhere.
// No email is real: an anonymous one is made up, an Apple one is built from the subject.
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

// `token` is SHA-256 of the session token, which is never stored (hashed-session-tokens.ts).
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

// `account_id` is the Apple subject; the unique index makes one Apple ID per user a database rule.
// No Apple token is kept.
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

// Better Auth requires this table even though no flow in use writes to it.
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

// `key_hash` is SHA-256 of the account key, which is never stored. The app keeps the key in the
// iCloud Keychain and signs in with it on every phone.
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

// Written when the partner deletes their account; the app shows it while the user is unpaired.
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

// `code_hash` is SHA-256 of the invite code, never stored. A user has one invite at a time.
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

// Keying on the user makes one partner per account a database rule.
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

// A block ends the pair and keeps the two from claiming each other's invites.
// Not foreign keys: the account erasure deletes the rows.
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

// What a user keeps when their pair ends: their share of coins and the bought items, given to the
// next pair's room on re-pairing. Not foreign keys: the account erasure deletes them.
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

// Kept after the pair or either account ends so a report can still be acted on; hence no foreign
// key on the pair id.
export const partnerReports = sqliteTable(
  "partner_reports",
  {
    id: text("id").primaryKey(),
    reporterId: text("reporter_id").notNull(),
    reportedId: text("reported_id").notNull(),
    pairId: text("pair_id").notNull(),
    reason: text("reason").notNull(),
    details: text("details"),
    // Not a key: the reported note may be gone.
    noteId: text("note_id"),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [index("partner_reports_reported_id_index").on(table.reportedId)],
);

// Dev stage only: the bot pairs like anyone else but has no device and never signs in.
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

// Fixed-window counters. `bucket` is SHA-256 of the route group and caller address, never the
// address itself. Old windows are deleted as new ones are written.
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

// A row is never updated, so changing weights or exposure later moves nobody; pairs outside an
// experiment have no row. Not a foreign key: a pair has no table, and rows outlive it for analysis.
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

// Per person, name and UTC day; nothing else is stored (no content, device, address or place).
// Names are a closed list in `contracts-domain/metrics`. Pair id: no foreign key, as `pair_flags`.
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
    // From the latest report that day (`clientInfoOf`); null for server-recorded names. Kept here
    // so the admin can split cohorts by build past Analytics Engine's 90 days.
    appVersion: text("app_version"),
    os: text("os"),
  },
  (table) => [
    primaryKey({ columns: [table.pairId, table.userId, table.name, table.day] }),
    index("pair_events_day_index").on(table.day),
  ],
);

// Per name, detail and UTC day, with the sum of values (a price in coins). No user and no pair.
// The rules for each name are `clientEventRules` in `contracts-domain/metrics`.
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

// `created_by` is the Cloudflare Access email. Nothing about any pair or person.
export const adminFunnels = sqliteTable("admin_funnels", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  definition: text("definition").notNull(),
  createdAt: integer("created_at").notNull(),
  createdBy: text("created_by").notNull(),
});

// The registry in `backend-flags/experiments` defines keys and variants; a row only overrides
// config. `version` goes up by one per save, so two editors cannot overwrite each other.
export const flagConfigs = sqliteTable("flag_configs", {
  key: text("key").primaryKey(),
  config: text("config").notNull(),
  version: integer("version").notNull(),
  updatedAt: integer("updated_at").notNull(),
  updatedBy: text("updated_by").notNull(),
});

// `by` is the Cloudflare Access email. Written in the same batch as the change itself.
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

// Forced variant for testing on the owner's phones: beats the stored assignment, never the kill
// switch. Not a foreign key, like `pair_flags`.
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

// One row per original transaction, so each is credited once. `owner_id` is a pair or
// `demo:<code>`, not a foreign key, so the record outlives the pair. No user or receipt is kept.
// `flagged` is 1 when a refund could not take the whole pack back.
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

// The balance is the sum of `amount`. Ids are stable (`purchase:<id>`, `refund:<id>`,
// `restore:<id>`) because the app merges entries by them.
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

// Keyed by Apple's UUID, so a retried notification is applied once.
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

// `option_ids` is a JSON array so the admin counts picks without reading `text`, the one typed
// column. A save keeps the row with the later `answered_at`.
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

// Items are never deleted: an id stays once sold. `asset` is JSON (`ShopAsset`). `version` goes up
// by one per save, so two editors cannot overwrite each other.
export const shopItems = sqliteTable(
  "shop_items",
  {
    id: text("id").primaryKey(),
    kind: text("kind").notNull(),
    name: text("name").notNull(),
    blurb: text("blurb"),
    mood: text("mood"),
    rarity: text("rarity").notNull(),
    price: integer("price").notNull(),
    salePrice: integer("sale_price"),
    saleFrom: integer("sale_from"),
    saleUntil: integer("sale_until"),
    dealDiscount: real("deal_discount"),
    dealOrder: integer("deal_order"),
    section: text("section").notNull(),
    sortOrder: integer("sort_order").notNull(),
    plus: integer("plus").notNull().default(0),
    isNew: integer("is_new").notNull().default(0),
    asset: text("asset").notNull(),
    minBuild: integer("min_build"),
    active: integer("active").notNull().default(1),
    version: integer("version").notNull().default(1),
    createdAt: integer("created_at").notNull(),
    createdBy: text("created_by").notNull(),
    updatedAt: integer("updated_at").notNull(),
    updatedBy: text("updated_by").notNull(),
  },
  (table) => [index("shop_items_order_index").on(table.sortOrder)],
);

// `by` is the Cloudflare Access email. Written in the same batch as the change itself.
export const shopItemChanges = sqliteTable(
  "shop_item_changes",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    itemId: text("item_id").notNull(),
    at: integer("at").notNull(),
    by: text("by").notNull(),
    action: text("action").notNull(),
    before: text("before"),
    after: text("after"),
  },
  (table) => [index("shop_item_changes_item_index").on(table.itemId, table.id)],
);

// The App Review partner (docs/app-review.md), paired with through a review code.
export const reviewPartners = sqliteTable("review_partners", {
  userId: text("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  createdAt: integer("created_at").notNull(),
});

// Only the SHA-256 is kept, plus the last four symbols for the panel. A new code revokes every
// earlier one.
export const reviewCodes = sqliteTable("review_codes", {
  codeHash: text("code_hash").primaryKey(),
  partnerId: text("partner_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  lastFour: text("last_four").notNull(),
  createdAt: integer("created_at").notNull(),
  createdBy: text("created_by").notNull(),
  expiresAt: integer("expires_at").notNull(),
  revokedAt: integer("revoked_at"),
  claims: integer("claims").notNull().default(0),
  lastClaimedAt: integer("last_claimed_at"),
});

// `by` is the Cloudflare Access email.
export const reviewChanges = sqliteTable("review_changes", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  at: integer("at").notNull(),
  by: text("by").notNull(),
  action: text("action").notNull(),
  lastFour: text("last_four"),
});
