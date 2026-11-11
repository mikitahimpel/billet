import {
  StoredAccountKey,
  StoredChallenge,
  StoredDevice,
  StoredPushToken,
  StoredUser,
} from "@billet/backend-auth/auth-repository";
import { StoredAssignment } from "@billet/backend-flags/flags-repository";
import { StoredDetail, StoredMetric } from "@billet/backend-metrics/metrics-repository";
import { StoredDemoPartner } from "@billet/backend-demo-partner/demo-partner-repository";
import {
  StoredBlock,
  StoredInvite,
  StoredKeptItem,
  StoredKeptWallet,
  StoredPairMember,
  StoredPartnerReport,
} from "@billet/backend-pairing/pairing-repository";
import {
  StoredReviewChange,
  StoredReviewCode,
  StoredReviewPartner,
} from "@billet/backend-review/review-repository";
import {
  StoredNotification,
  StoredPurchase,
  StoredPurchaseEntry,
} from "@billet/backend-payments/payments-repository";
import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";
import { describe, expect, it } from "vitest";
import * as directorySchema from "../src/directory-schema.ts";
import { ShopChangeRow, ShopItemRow } from "../src/shop-store-live.ts";
import {
  accountKeys,
  adminFunnels,
  appStoreNotifications,
  authAccounts,
  authChallenges,
  authSessions,
  authUsers,
  authVerifications,
  demoPartners,
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
  partnerReports,
  blocks,
  keptItems,
  keptWallets,
  shopItemChanges,
  shopItems,
  purchases,
  pushTokens,
  rateLimits,
  coinLedger,
  reviewChanges,
  reviewCodes,
  reviewPartners,
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
  StoredActivity,
  StoredActivityRead,
  StoredCat,
  StoredCatEntry,
  StoredDelivery,
  StoredNote,
  StoredOwnedInk,
  StoredOwnedItem,
  StoredWish,
  StoredPlacement,
  StoredLayoutLog,
  StoredStowedPiece,
  StoredGiftLoves,
  StoredGiftPlan,
  StoredGiftWish,
  StoredList,
  StoredListItem,
  StoredListKey,
  StoredReaction,
  StoredClaimedBonus,
  StoredMood,
  StoredMovieSwipe,
  StoredGuessAnswer,
  StoredGuessRound,
  StoredGuessWeek,
  StoredRiddle,
  StoredRiddleGuess,
  StoredRiddleSeries,
  StoredCoinEntry,
  StoredWallet,
  StoredRoom,
} from "../src/room-rows.ts";
import * as roomSchema from "../src/room-schema.ts";
import {
  activity,
  activityRead,
  cat,
  catEntry,
  coinEntry,
  delivery,
  note,
  ownedInk,
  ownedItem,
  placement,
  layoutLog,
  stowedPiece,
  reaction,
  room,
  wallet,
  wish,
  claimedBonus,
  mood,
  movieSwipes,
  guessAnswers,
  guessRounds,
  guessWeeks,
  riddleGuesses,
  riddleSeries,
  riddles,
  giftLoves,
  giftPlan,
  giftWish,
  listItems,
  listKeys,
  lists,
} from "../src/room-schema.ts";
import { domainShape, tableShape } from "./schema-drift.ts";
import { getTableName, tablesOf } from "./table-columns.ts";

// drizzle-orm/effect-schema derives from tables, the domain is hand-written: neither generates
// the other. Every exported table needs its domain type here, or the test below fails.
const checked = [
  ["account_keys", accountKeys, StoredAccountKey],
  ["admin_funnels", adminFunnels, FunnelRow],
  ["app_store_notifications", appStoreNotifications, StoredNotification],
  ["auth_account", authAccounts, AuthAccountRow],
  ["auth_challenges", authChallenges, StoredChallenge],
  ["auth_session", authSessions, AuthSessionRow],
  ["auth_user", authUsers, AuthUserRow],
  ["auth_verification", authVerifications, AuthVerificationRow],
  ["demo_partners", demoPartners, StoredDemoPartner],
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
  ["blocks", blocks, StoredBlock],
  ["kept_wallets", keptWallets, StoredKeptWallet],
  ["kept_items", keptItems, StoredKeptItem],
  ["partner_reports", partnerReports, StoredPartnerReport],
  ["purchases", purchases, StoredPurchase],
  ["shop_items", shopItems, ShopItemRow],
  ["shop_item_changes", shopItemChanges, ShopChangeRow],
  ["push_tokens", pushTokens, StoredPushToken],
  ["rate_limits", rateLimits, StoredRateLimit],
  ["review_changes", reviewChanges, StoredReviewChange],
  ["review_codes", reviewCodes, StoredReviewCode],
  ["review_partners", reviewPartners, StoredReviewPartner],
  ["coin_ledger", coinLedger, StoredPurchaseEntry],
  ["activity", activity, StoredActivity],
  ["activity_read", activityRead, StoredActivityRead],
  ["cat", cat, StoredCat],
  ["cat_entry", catEntry, StoredCatEntry],
  ["coin_entry", coinEntry, StoredCoinEntry],
  ["delivery", delivery, StoredDelivery],
  ["gift_loves", giftLoves, StoredGiftLoves],
  ["gift_plan", giftPlan, StoredGiftPlan],
  ["gift_wish", giftWish, StoredGiftWish],
  ["lists", lists, StoredList],
  ["list_items", listItems, StoredListItem],
  ["list_keys", listKeys, StoredListKey],
  ["note", note, StoredNote],
  ["owned_ink", ownedInk, StoredOwnedInk],
  ["owned_item", ownedItem, StoredOwnedItem],
  ["reaction", reaction, StoredReaction],
  ["claimed_bonus", claimedBonus, StoredClaimedBonus],
  ["mood", mood, StoredMood],
  ["movie_swipes", movieSwipes, StoredMovieSwipe],
  ["guess_rounds", guessRounds, StoredGuessRound],
  ["guess_answers", guessAnswers, StoredGuessAnswer],
  ["guess_weeks", guessWeeks, StoredGuessWeek],
  ["riddles", riddles, StoredRiddle],
  ["riddle_guesses", riddleGuesses, StoredRiddleGuess],
  ["riddle_series", riddleSeries, StoredRiddleSeries],
  ["room", room, StoredRoom],
  ["users", users, StoredUser],
  ["wallet", wallet, StoredWallet],
  ["wish", wish, StoredWish],
  ["placement", placement, StoredPlacement],
  ["layout_log", layoutLog, StoredLayoutLog],
  ["stowed_piece", stowedPiece, StoredStowedPiece],
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
