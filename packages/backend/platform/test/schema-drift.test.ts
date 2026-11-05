import {
  StoredAccountKey,
  StoredChallenge,
  StoredDevice,
  StoredPushToken,
  StoredUser,
} from "@billet/backend-auth/auth-repository";
import { StoredAssignment } from "@billet/backend-flags/flags-repository";
import { StoredDetail, StoredMetric } from "@billet/backend-metrics/metrics-repository";
import { StoredInvite, StoredPairMember } from "@billet/backend-pairing/pairing-repository";
import {
  StoredNotification,
  StoredPurchase,
  StoredPurchaseEntry,
} from "@billet/backend-payments/payments-repository";
import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";
import { describe, expect, it } from "vitest";
import * as directorySchema from "../src/directory-schema.ts";
import {
  accountKeys,
  adminFunnels,
  appStoreNotifications,
  authAccounts,
  authChallenges,
  authSessions,
  authUsers,
  authVerifications,
  devices,
  flagChanges,
  flagConfigs,
  invites,
  eventDetails,
  onboardingAnswers,
  pairEvents,
  pairFlagOverrides,
  pairFlags,
  pairMembers,
  partnerNotices,
  purchases,
  pushTokens,
  rateLimits,
  coinLedger,
  users,
} from "../src/directory-schema.ts";
import {
  AuthAccountRow,
  AuthSessionRow,
  AuthUserRow,
  AuthVerificationRow,
} from "../src/better-auth-rows.ts";
import { StoredPartnerNotice } from "../src/account-repository-live.ts";
import { StoredRateLimit } from "../src/rate-limit.ts";
import { OnboardingAnswerRow } from "../src/onboarding-repository-live.ts";
import { FunnelRow } from "../src/funnel-store-live.ts";
import {
  FlagChangeRow,
  FlagConfigRow,
  PairOverrideRow,
} from "../src/flag-config-repository-live.ts";
import {
  SampleRow,
  StoredCat,
  StoredCatEntry,
  StoredDelivery,
  StoredNote,
  StoredOwnedInk,
  StoredRoom,
} from "../src/room-rows.ts";
import * as roomSchema from "../src/room-schema.ts";
import { cat, catEntry, delivery, note, ownedInk, room } from "../src/room-schema.ts";
import { domainShape, tableShape } from "./schema-drift.ts";
import { getTableName, tablesOf } from "./table-columns.ts";

// `drizzle-orm/effect-schema` derives from tables, while the domain is hand-written with brands and
// tagged unions, so neither can generate the other. Every exported table needs its domain type here: the test below
// fails on one that is missing.
const checked = [
  ["account_keys", accountKeys, StoredAccountKey],
  ["admin_funnels", adminFunnels, FunnelRow],
  ["app_store_notifications", appStoreNotifications, StoredNotification],
  ["auth_account", authAccounts, AuthAccountRow],
  ["auth_challenges", authChallenges, StoredChallenge],
  ["auth_session", authSessions, AuthSessionRow],
  ["auth_user", authUsers, AuthUserRow],
  ["auth_verification", authVerifications, AuthVerificationRow],
  ["devices", devices, StoredDevice],
  ["flag_changes", flagChanges, FlagChangeRow],
  ["flag_configs", flagConfigs, FlagConfigRow],
  ["pair_flag_overrides", pairFlagOverrides, PairOverrideRow],
  ["invites", invites, StoredInvite],
  ["event_details", eventDetails, StoredDetail],
  ["onboarding_answers", onboardingAnswers, OnboardingAnswerRow],
  ["pair_events", pairEvents, StoredMetric],
  ["pair_flags", pairFlags, StoredAssignment],
  ["pair_members", pairMembers, StoredPairMember],
  ["partner_notices", partnerNotices, StoredPartnerNotice],
  ["purchases", purchases, StoredPurchase],
  ["push_tokens", pushTokens, StoredPushToken],
  ["rate_limits", rateLimits, StoredRateLimit],
  ["coin_ledger", coinLedger, StoredPurchaseEntry],
  ["cat", cat, StoredCat],
  ["cat_entry", catEntry, StoredCatEntry],
  ["delivery", delivery, StoredDelivery],
  ["note", note, StoredNote],
  ["owned_ink", ownedInk, StoredOwnedInk],
  ["room", room, StoredRoom],
  ["users", users, StoredUser],
] as const;

describe("tables match their Effect Schema", () => {
  it.each(checked)("%s", (_, table, domain) => {
    expect(tableShape(table)).toEqual(domainShape(domain));
  });

  it("covers every table the schema modules export", () => {
    const exported = [...tablesOf(directorySchema), ...tablesOf(roomSchema)].map(getTableName);
    expect(exported.length).toBeGreaterThan(0);
    expect(checked.map(([name]) => name).toSorted()).toEqual(exported.toSorted());
  });

  it.each([
    [
      "a renamed column",
      sqliteTable("t", { id: text("id").primaryKey(), created: integer("c").notNull() }),
    ],
    [
      "a changed type",
      sqliteTable("t", { id: text("id").primaryKey(), createdAt: text("c").notNull() }),
    ],
    [
      "a nullable column",
      sqliteTable("t", { id: text("id").primaryKey(), createdAt: integer("c") }),
    ],
    [
      "an extra column",
      sqliteTable("t", {
        id: text("id").primaryKey(),
        createdAt: integer("c").notNull(),
        extra: text("e").notNull(),
      }),
    ],
  ])("catches %s", (_, table) => {
    expect(tableShape(table)).not.toEqual(domainShape(SampleRow));
  });
});
