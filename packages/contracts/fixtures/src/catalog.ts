import { Schema } from "effect";
import {
  ActivityCursor,
  ActivityEvent,
  ActivityItem,
  ActivityTarget,
} from "@billet/contracts-domain/activity";
import { CatEntry, CatEvent, CatNeeds, CatProfile, CatTemper } from "@billet/contracts-domain/cat";
import { DeliveryLane } from "@billet/contracts-domain/delivery-lane";
import {
  DeviceId,
  IdempotencyKey,
  InviteCode,
  MediaKey,
  NoteId,
  UserId,
} from "@billet/contracts-domain/ids";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { CompactStrokes, Stroke } from "@billet/contracts-domain/ink";
import { freeInk, Ink, InkId, inkOf, inks } from "@billet/contracts-domain/inks";
import { Note } from "@billet/contracts-domain/note";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PushToken } from "@billet/contracts-domain/push-token";
import { AccountResponse, DeleteAccountRequest } from "@billet/contracts-http-api/account";
import { ApiError } from "@billet/contracts-http-api/api-error";
import {
  AccountKey,
  AuthChallengeResponse,
  AuthNonce,
  IdentityToken,
  SessionResponse,
  SessionToken,
  SignInAnonymouslyRequest,
  SignInWithAppleRequest,
} from "@billet/contracts-http-api/auth";
import { RegisterPushTokenRequest } from "@billet/contracts-http-api/device";
import { ReportEventsRequest } from "@billet/contracts-http-api/events";
import { FlagsResponse } from "@billet/contracts-http-api/flags";
import { BuyRequest, BuyResponse, CoinsResponse } from "@billet/contracts-http-api/coins";
import { InksResponse } from "@billet/contracts-http-api/inks";
import { PairResponse } from "@billet/contracts-http-api/pair";
import {
  OrderRequest,
  OrderResponse,
  ShopResponse,
  WishRequest,
} from "@billet/contracts-http-api/shop";
import { PieceSetId, RoomItemId, ShopOffer } from "@billet/contracts-domain/shop";
import { CoinEntry } from "@billet/contracts-domain/coins";
import {
  type AppStatus,
  MaintenanceResponse,
  StatusResponse,
} from "@billet/contracts-http-api/status";
import {
  ClaimInviteRequest,
  ClaimInviteResponse,
  CreateInviteResponse,
} from "@billet/contracts-http-api/invite";
import {
  AppStoreNotificationRequest,
  MockPurchaseRequest,
  PurchaseRequest,
  PurchaseResponse,
  PurchasesResponse,
} from "@billet/contracts-http-api/purchase";
import {
  ListNotesResponse,
  SendNoteRequest,
  SendNoteResponse,
  UploadImageResponse,
} from "@billet/contracts-http-api/note";
import {
  OnboardingResponse,
  SaveOnboardingAnswerRequest,
} from "@billet/contracts-http-api/onboarding";
import { OnboardingAnswer, OnboardingStep } from "@billet/contracts-domain/onboarding";
import {
  CatJournalResponse,
  CatResponse,
  RecordCatEventRequest,
  RecordCatEventResponse,
  SaveCatRequest,
} from "@billet/contracts-http-api/cat";
import {
  ActivityResponse,
  ActivityUnreadResponse,
  MarkActivityReadRequest,
} from "@billet/contracts-http-api/activity";
import { ClientMessage } from "@billet/contracts-realtime/client-message";
import { ServerMessage } from "@billet/contracts-realtime/server-message";
import { PushPayload } from "@billet/contracts-push/push-payload";

export interface Fixture {
  /** Swift type name and golden directory name. */
  readonly name: string;
  readonly schema: Schema.Codec<unknown, unknown>;
  /** Sample values by file name. */
  readonly samples: Readonly<Record<string, unknown>>;
  /** For tagged unions: the `_tag`s that must each have a sample. */
  readonly tags?: ReadonlyArray<string>;
}

const fixture = <S extends Schema.Codec<unknown, unknown>>(
  name: string,
  schema: S,
  samples: Record<string, S["Type"]>,
): Fixture => {
  const cases = (schema as { cases?: Record<string, unknown> }).cases;
  return cases === undefined
    ? { name, schema, samples }
    : { name, schema, samples, tags: Object.keys(cases) };
};

const alice = Schema.decodeUnknownSync(UserId)("user-alice");
const bob = Schema.decodeUnknownSync(UserId)("user-bob");
const noteId = Schema.decodeUnknownSync(NoteId)("note-1");
const image = Schema.decodeUnknownSync(MediaKey)("pairs/pair-1/notes/note-1.png");
const pairId = Schema.decodeUnknownSync(PairId)("pair-1");
const code = Schema.decodeUnknownSync(InviteCode)("ABCD2345EF");
const experimentKey = Schema.decodeUnknownSync(ExperimentKey)("home-direction");
const otherExperimentKey = Schema.decodeUnknownSync(ExperimentKey)("invite-card");
const variantId = Schema.decodeUnknownSync(VariantId)("window-seat");
const otherVariantId = Schema.decodeUnknownSync(VariantId)("control");
const idempotencyKey = Schema.decodeUnknownSync(IdempotencyKey)(
  "6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f",
);

const deviceId = Schema.decodeUnknownSync(DeviceId)("device-1");
// Sample shapes only: none of these was ever a real credential.
const nonce = Schema.decodeUnknownSync(AuthNonce)("nonce-sample-".padEnd(43, "0"));
const sessionToken = Schema.decodeUnknownSync(SessionToken)("session-sample-".padEnd(43, "0"));
const accountKey = Schema.decodeUnknownSync(AccountKey)("account-key-sample-".padEnd(43, "0"));
const identityToken = Schema.decodeUnknownSync(IdentityToken)("header.payload.signature");
const pushToken = Schema.decodeUnknownSync(PushToken)("ab".repeat(32));

const stroke: Stroke = Stroke.make({
  color: "#B8485F",
  width: 4.5,
  points: [
    { x: 0.25, y: 0.5 },
    { x: 0.75, y: 1.5 },
  ],
});
const compact: CompactStrokes = CompactStrokes.make({
  version: 1,
  strokes: [{ color: "#2A1A1C", width: 3, points: [10, 20, 30, 40] }],
});

const drawing = Note.cases.Drawing.make({
  id: noteId,
  author: alice,
  sentAt: 1_700_000_000_000,
  compact,
  image,
});
// Stored before photos carried a size and a preview: it must still decode.
const photo = Note.cases.Photo.make({ id: noteId, author: bob, sentAt: 1_700_000_001_000, image });
const photoImage = Schema.decodeUnknownSync(MediaKey)("pairs/pair-1/notes/note-2.jpg");
const photoShape = {
  image: photoImage,
  width: 3024,
  height: 4032,
  preview: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
} as const;
const photoWithCaption = Note.cases.Photo.make({
  id: noteId,
  author: bob,
  sentAt: 1_700_000_001_000,
  ...photoShape,
  caption: "sunset from the bridge 🌉",
});
const photoWithoutCaption = Note.cases.Photo.make({
  id: noteId,
  author: bob,
  sentAt: 1_700_000_001_000,
  ...photoShape,
});
const drawingOnPaper = Note.cases.Drawing.make({
  id: noteId,
  author: alice,
  sentAt: 1_700_000_000_000,
  compact,
  image,
  paper: "sage",
});
const rose = Schema.decodeSync(InkId)("ink-rose");
const decodeCoinEntry = Schema.decodeUnknownSync(CoinEntry);
const lamp = Schema.decodeSync(RoomItemId)("lamp");
const rug = Schema.decodeSync(RoomItemId)("rug");
const tower = Schema.decodeSync(RoomItemId)("tower");
const yarn = Schema.decodeSync(RoomItemId)("yarn");
const readingNook = Schema.decodeSync(PieceSetId)("reading-nook");
const earnEntry = decodeCoinEntry({
  id: "earn:6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f",
  kind: "earn",
  amount: 10,
  ref: "6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f",
  at: 1762350000000,
});
const spendEntry = decodeCoinEntry({
  id: "spend:0c9a8b7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d",
  kind: "spend",
  amount: -60,
  ref: "ink-rose",
  at: 1762350060000,
});
const catalogInk = (id: string): Ink => {
  const found = inkOf(id);
  if (found === undefined) throw new Error(`no ink ${id} in the catalog`);
  return found;
};
const text = Note.cases.Text.make({
  id: noteId,
  author: bob,
  sentAt: 1_700_000_002_000,
  text: "miss you already 💛",
  paper: "butter",
  ink: rose,
});
const plainText = Note.cases.Text.make({
  id: noteId,
  author: alice,
  sentAt: 1_700_000_003_000,
  text: "home soon",
  ink: freeInk,
});

const maintenanceStatus: AppStatus = {
  maintenance: {
    active: true,
    message: { key: "maintenance.default", text: "billet is resting for a little while." },
    until: "2026-11-03T22:30:00Z",
  },
  minVersion: "1.0",
};

const onboardingStep = Schema.decodeUnknownSync(OnboardingStep);
const onboardingTitle = (en: string, ru: string) => ({ en, ru });
const ageStep = onboardingStep({
  _tag: "Single",
  id: "age",
  title: onboardingTitle("How old are you?", "Сколько тебе лет?"),
  subtitle: onboardingTitle("Only you see this.", "Это видишь только ты."),
  skippable: true,
  options: [
    { id: "age-18-24", label: onboardingTitle("18–24", "18–24") },
    { id: "age-45-plus", label: onboardingTitle("45+", "45+") },
  ],
});
const goalsStep = onboardingStep({
  _tag: "Multi",
  id: "goals",
  title: onboardingTitle("What do you want to do together?", "Что вы хотите делать вместе?"),
  skippable: true,
  options: [
    { id: "widgets", label: onboardingTitle("Use widgets", "Пользоваться виджетами"), emoji: "📱" },
    {
      id: "just-exploring",
      label: onboardingTitle("Just exploring", "Просто смотрю"),
      exclusive: true,
    },
  ],
});
const rangeStep = onboardingStep({
  _tag: "Range",
  id: "notes-a-day",
  title: onboardingTitle("How many notes a day?", "Сколько записок в день?"),
  skippable: true,
  min: 0,
  max: 10,
  step: 1,
  unit: onboardingTitle("notes", "записок"),
});
const nameStep = onboardingStep({
  _tag: "Text",
  id: "name",
  title: onboardingTitle("What does your person call you?", "Как тебя называет твой человек?"),
  skippable: true,
  placeholder: onboardingTitle("Your name", "Имя"),
  maxLength: 20,
});
const onboardingAnswer = Schema.decodeUnknownSync(OnboardingAnswer);

const catProfile = Schema.decodeUnknownSync(CatProfile)({
  name: "Mochi",
  look: { model: "marmalade", coat: "natural" },
  bornAt: 1_700_000_000_000,
  natureSeed: "12345678901234567890",
  utcOffsetSeconds: 3600,
});
const catEvents = {
  fed: { _tag: "Fed", grams: 40 },
  petted: { _tag: "Petted" },
  played: { _tag: "Played" },
  watered: { _tag: "Watered" },
  "note-shared": { _tag: "NoteShared", note: "note-1", kind: "Photo" },
  "game-played": { _tag: "GamePlayed", game: "laser", score: 7, won: true },
  slept: { _tag: "Slept" },
  shooed: { _tag: "Shooed" },
} as const;
const catEvent = (name: keyof typeof catEvents): CatEvent =>
  Schema.decodeUnknownSync(CatEvent)(catEvents[name]);
const catEntry = (seq: number, name: keyof typeof catEvents, by = alice): CatEntry =>
  Schema.decodeUnknownSync(CatEntry)({
    seq,
    id: idempotencyKey,
    by,
    at: 1_700_000_100_000 + seq * 1000,
    event: catEvents[name],
  });
const catTemper: CatTemper = { curious: 0.5, lazy: 0.46, cuddly: 0.62 };
const catNeeds: CatNeeds = {
  at: 1_700_000_200_000,
  full: 0.81,
  rested: 0.64,
  loved: 0.52,
  playful: 0.43,
  mood: 0.57,
  asleep: false,
};
const lonelyCatNeeds: CatNeeds = { ...catNeeds, loved: 0.31, missing: bob };

const activityEvents = {
  "cat-fed": { _tag: "CatFed", grams: 40 },
  "cat-petted": { _tag: "CatPetted" },
  "cat-played": { _tag: "CatPlayed" },
  "cat-game-played": { _tag: "CatGamePlayed", game: "laser", score: 7, won: true },
  "cat-slept": { _tag: "CatSlept" },
  "cat-shooed": { _tag: "CatShooed" },
  "plant-watered": { _tag: "PlantWatered", plant: "monstera" },
  "plant-watered-by-the-window": { _tag: "PlantWatered" },
  "cat-adopted": { _tag: "CatAdopted", name: "Mochi" },
  "cat-renamed": { _tag: "CatRenamed", name: "Мочи 🐾" },
  "note-sent": { _tag: "NoteSent", note: "note-1", kind: "Drawing" },
  purchased: {
    _tag: "Purchased",
    offer: "bundle:starter-ink",
    items: ["ink-rose", "armchair"],
    coins: 120,
  },
  "purchased-one": { _tag: "Purchased", items: ["armchair"], coins: 80 },
  "gift-claimed": { _tag: "GiftClaimed", coins: 10 },
  "bonus-earned": { _tag: "BonusEarned", collection: "cozy-cabin", coins: 50 },
  "coins-bought": {
    _tag: "CoinsBought",
    productId: "com.mikitahimpel.billet.coins.small",
    coins: 500,
  },
  refunded: { _tag: "Refunded", productId: "com.mikitahimpel.billet.coins.small", coins: 500 },
  "streak-reached": { _tag: "StreakReached", days: 7 },
} as const;
const activityTargets = {
  note: { _tag: "Note", note: "note-1" },
  moments: { _tag: "Moments", note: "note-1" },
  cat: { _tag: "Cat" },
  plant: { _tag: "Plant", plant: "monstera" },
  "shop-item": { _tag: "ShopItem", id: "armchair" },
  "shop-offer": { _tag: "ShopOffer", id: "deal:2026-11-05:0" },
} as const;
const decodeSamples = <S extends Schema.Codec<unknown, unknown>>(
  schema: S,
  samples: Readonly<Record<string, unknown>>,
): Record<string, S["Type"]> =>
  Object.fromEntries(
    Object.entries(samples).map(([name, sample]) => [
      name,
      Schema.decodeUnknownSync(schema)(sample),
    ]),
  );
const decodeActivityItem = Schema.decodeUnknownSync(ActivityItem);
/** The server's cursor for an item: its time, zero-padded, then its id. */
const activityItem = (item: {
  readonly id: string;
  readonly at: number;
  readonly [key: string]: unknown;
}) => decodeActivityItem({ ...item, cursor: `${String(item.at).padStart(16, "0")}~${item.id}` });
const fedItem = activityItem({
  id: `cat:${idempotencyKey}`,
  at: 1_700_000_101_000,
  actor: "Partner",
  event: activityEvents["cat-fed"],
  target: activityTargets.cat,
});
const drawingItem = activityItem({
  id: "note:note-1",
  at: 1_700_000_100_000,
  actor: "Me",
  event: activityEvents["note-sent"],
  target: activityTargets.moments,
});
const refundItem = activityItem({
  id: "refund:2000000123456789",
  at: 1_700_000_099_000,
  actor: "Store",
  event: activityEvents.refunded,
});
const activityCursor = Schema.decodeUnknownSync(ActivityCursor)(`0001700000100000~note:note-1`);

export const catalog: ReadonlyArray<Fixture> = [
  fixture("PairId", PairId, { default: pairId }),
  fixture("CompactStrokes", CompactStrokes, { default: compact }),
  fixture("Stroke", Stroke, { default: stroke }),
  fixture("Note", Note, {
    drawing,
    "drawing-on-paper": drawingOnPaper,
    photo,
    "photo-with-caption": photoWithCaption,
    "photo-without-caption": photoWithoutCaption,
    text,
    "text-without-paper": plainText,
  }),
  fixture("DeliveryLane", DeliveryLane, {
    "web-socket": DeliveryLane.cases.WebSocket.make({}),
    "widget-push": DeliveryLane.cases.WidgetPush.make({}),
    "alert-push": DeliveryLane.cases.AlertPush.make({}),
    "timeline-refresh": DeliveryLane.cases.TimelineRefresh.make({}),
    "live-activity-push": DeliveryLane.cases.LiveActivityPush.make({}),
  }),
  fixture("CreateInviteResponse", CreateInviteResponse, {
    default: { code, expiresAt: 1_700_086_400_000 },
  }),
  fixture("ClaimInviteRequest", ClaimInviteRequest, { default: { code } }),
  fixture("ClaimInviteResponse", ClaimInviteResponse, { default: { pairId } }),
  fixture("UploadImageResponse", UploadImageResponse, { default: { image } }),
  fixture("SendNoteRequest", SendNoteRequest, {
    drawing: SendNoteRequest.cases.Drawing.make({ key: idempotencyKey, compact, image }),
    "drawing-on-paper": SendNoteRequest.cases.Drawing.make({
      key: idempotencyKey,
      compact,
      image,
      paper: "blush",
    }),
    photo: SendNoteRequest.cases.Photo.make({ key: idempotencyKey, ...photoShape }),
    "photo-with-caption": SendNoteRequest.cases.Photo.make({
      key: idempotencyKey,
      ...photoShape,
      caption: "sunset from the bridge 🌉",
    }),
    text: SendNoteRequest.cases.Text.make({
      key: idempotencyKey,
      text: "miss you already 💛",
      paper: "butter",
      ink: rose,
    }),
    "text-without-paper": SendNoteRequest.cases.Text.make({
      key: idempotencyKey,
      text: "home soon",
      ink: freeInk,
    }),
  }),
  fixture("SendNoteResponse", SendNoteResponse, { default: { note: drawing } }),
  fixture("ReportEventsRequest", ReportEventsRequest, {
    default: { events: ["AppOpened", "WidgetAdded"] },
    none: { events: [] },
    detailed: {
      events: [
        { name: "AppOpened" },
        { name: "CatChosen", detail: "idolIlya" },
        { name: "NoteOpened", detail: "widget" },
        { name: "ShopItemBought", detail: "fairy-lights", value: 40 },
        "CatPetted",
      ],
    },
  }),
  fixture("StatusResponse", StatusResponse, {
    normal: { status: { maintenance: { active: false } } },
    maintenance: { status: maintenanceStatus },
    "update-and-notice": {
      status: {
        maintenance: { active: false },
        minVersion: "1.2.0+14",
        notice: { key: "notice.slow-notes", text: "Notes may be slow tonight." },
      },
    },
    "analytics-off": {
      status: { maintenance: { active: false }, analytics: { enabled: false } },
    },
  }),
  fixture("MaintenanceResponse", MaintenanceResponse, {
    default: { error: "maintenance", status: maintenanceStatus },
  }),
  fixture("FlagsResponse", FlagsResponse, {
    "with-status": {
      flags: [{ key: experimentKey, variant: variantId }],
      status: maintenanceStatus,
    },
    default: {
      flags: [
        { key: experimentKey, variant: variantId },
        { key: otherExperimentKey, variant: otherVariantId },
      ],
    },
    none: { flags: [] },
  }),
  fixture("ListNotesResponse", ListNotesResponse, {
    default: {
      notes: [
        { seq: 1, note: drawing },
        { seq: 2, note: photo },
        { seq: 3, note: text },
      ],
    },
  }),
  fixture("AuthChallengeResponse", AuthChallengeResponse, {
    default: { nonce, expiresAt: 1_700_000_300_000 },
  }),
  fixture("SignInWithAppleRequest", SignInWithAppleRequest, { default: { identityToken } }),
  fixture("SignInAnonymouslyRequest", SignInAnonymouslyRequest, { default: { accountKey } }),
  fixture("AccountResponse", AccountResponse, {
    anonymous: { userId: alice, linked: false },
    linked: { userId: alice, linked: true },
    "partner-left": {
      userId: alice,
      linked: false,
      partnerLeft: { reason: "account-deleted", at: 1_700_000_400_000 },
    },
  }),
  fixture("DeleteAccountRequest", DeleteAccountRequest, {
    anonymous: {},
    linked: { appleAuthorizationCode: "c0ffee.0.abcd.code" },
  }),
  fixture("SessionResponse", SessionResponse, {
    default: { sessionToken, expiresAt: 1_707_776_000_000, userId: alice, deviceId },
  }),
  fixture("RegisterPushTokenRequest", RegisterPushTokenRequest, {
    alert: { kind: "alert", environment: "production", token: pushToken },
    widget: { kind: "widget", environment: "sandbox", token: pushToken },
    "live-activity": { kind: "liveactivity", environment: "production", token: pushToken },
  }),
  fixture("ApiError", ApiError, {
    unauthorized: ApiError.cases.Unauthorized.make({}),
    "invalid-request": ApiError.cases.InvalidRequest.make({}),
    unavailable: ApiError.cases.Unavailable.make({}),
    "not-found": ApiError.cases.NotFound.make({}),
    "invalid-invite": ApiError.cases.InvalidInvite.make({}),
    "already-paired": ApiError.cases.AlreadyPaired.make({}),
    "apple-id-in-use": ApiError.cases.AppleIdInUse.make({}),
    "invalid-purchase": ApiError.cases.InvalidPurchase.make({}),
    "ink-not-owned": ApiError.cases.InkNotOwned.make({ ink: rose }),
    "not-enough-coins": ApiError.cases.NotEnoughCoins.make({ needed: 60, have: 25 }),
    "already-owned": ApiError.cases.AlreadyOwned.make({ itemId: "ink-rose" }),
  }),
  fixture("CoinEntry", CoinEntry, {
    default: earnEntry,
    spend: spendEntry,
  }),
  fixture("CoinsResponse", CoinsResponse, {
    default: { balance: 65, entries: [earnEntry, spendEntry] },
    empty: { balance: 0, entries: [] },
  }),
  fixture("BuyRequest", BuyRequest, { default: { id: idempotencyKey, item: rose } }),
  fixture("BuyResponse", BuyResponse, {
    default: { entry: spendEntry, balance: 65, granted: [rose], owned: [freeInk, rose] },
  }),
  fixture("Ink", Ink, { free: catalogInk("ink-graphite"), default: catalogInk("ink-rose") }),
  fixture("InksResponse", InksResponse, {
    default: { inks, owned: [freeInk, rose] },
    "free-only": { inks, owned: [freeInk] },
  }),
  fixture("ShopOffer", ShopOffer, {
    ink: ShopOffer.cases.Ink.make({ ink: rose }),
    item: ShopOffer.cases.Item.make({ item: tower }),
    set: ShopOffer.cases.Set.make({ set: readingNook }),
    treat: ShopOffer.cases.Treat.make({}),
  }),
  fixture("ShopResponse", ShopResponse, {
    default: { balance: 65, inks: [freeInk, rose], items: [lamp, rug, tower], wishlist: [yarn] },
    new: { balance: 0, inks: [freeInk], items: [lamp, rug], wishlist: [] },
  }),
  fixture("OrderRequest", OrderRequest, {
    default: { id: idempotencyKey, offer: ShopOffer.cases.Item.make({ item: tower }) },
    treat: { id: idempotencyKey, offer: ShopOffer.cases.Treat.make({}) },
  }),
  fixture("OrderResponse", OrderResponse, {
    default: {
      entry: { ...spendEntry, amount: -540, ref: "tower" },
      shop: { balance: 65, inks: [freeInk], items: [lamp, rug, tower], wishlist: [] },
    },
  }),
  fixture("WishRequest", WishRequest, {
    wished: { item: tower, wished: true },
    unwished: { item: tower, wished: false },
  }),
  fixture("PairResponse", PairResponse, { default: { pairId, members: [alice, bob] } }),
  // A JWS's shape only: never signed by anyone.
  fixture("PurchaseRequest", PurchaseRequest, {
    default: {
      signedTransaction: "eyJhbGciOiJFUzI1NiJ9.eyJ0cmFuc2FjdGlvbklkIjoiMSJ9.c2lnbmF0dXJl",
    },
  }),
  fixture("MockPurchaseRequest", MockPurchaseRequest, {
    purchase: {
      productId: "com.mikitahimpel.billet.coins.100",
      transactionId: "mock-6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f",
      kind: "purchase",
    },
    refund: {
      productId: "com.mikitahimpel.billet.coins.100",
      transactionId: "mock-6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f",
      kind: "refund",
    },
  }),
  fixture("PurchaseResponse", PurchaseResponse, {
    default: {
      transactionId: "2000000812345678",
      productId: "com.mikitahimpel.billet.coins.550",
      coins: 550,
      balance: 1234,
      duplicate: false,
    },
    duplicate: {
      transactionId: "2000000812345678",
      productId: "com.mikitahimpel.billet.coins.550",
      coins: 550,
      balance: 1234,
      duplicate: true,
    },
  }),
  fixture("PurchasesResponse", PurchasesResponse, {
    default: {
      balance: 550,
      entries: [
        {
          id: "purchase:2000000812345678",
          kind: "purchase",
          amount: 100,
          productId: "com.mikitahimpel.billet.coins.100",
          at: "2026-11-04T15:00:00.000Z",
        },
        {
          id: "purchase:2000000812345679",
          kind: "purchase",
          amount: 550,
          productId: "com.mikitahimpel.billet.coins.550",
          at: "2026-11-04T15:05:00.000Z",
        },
        {
          id: "refund:2000000812345678",
          kind: "refund",
          amount: -100,
          productId: "com.mikitahimpel.billet.coins.100",
          at: "2026-11-05T09:30:00.000Z",
        },
      ],
    },
    empty: { balance: 0, entries: [] },
  }),
  fixture("AppStoreNotificationRequest", AppStoreNotificationRequest, {
    default: { signedPayload: "eyJhbGciOiJFUzI1NiJ9.eyJub3RpZmljYXRpb25UeXBlIjoiUkVGVU5EIn0.c2ln" },
  }),
  fixture("OnboardingStep", OnboardingStep, {
    single: ageStep,
    multi: goalsStep,
    range: rangeStep,
    text: nameStep,
  }),
  fixture("OnboardingAnswer", OnboardingAnswer, {
    skipped: onboardingAnswer({ _tag: "Skipped" }),
    single: onboardingAnswer({ _tag: "Single", option: "age-25-34" }),
    multi: onboardingAnswer({ _tag: "Multi", options: ["widgets", "raise-pet"] }),
    range: onboardingAnswer({ _tag: "Range", value: 3 }),
    text: onboardingAnswer({ _tag: "Text", text: "Лев 💛" }),
  }),
  fixture("OnboardingResponse", OnboardingResponse, {
    default: {
      version: Schema.decodeUnknownSync(OnboardingResponse.fields.version)("2026-11-04"),
      steps: [ageStep, goalsStep, rangeStep, nameStep],
    },
  }),
  fixture("SaveOnboardingAnswerRequest", SaveOnboardingAnswerRequest, {
    single: Schema.decodeUnknownSync(SaveOnboardingAnswerRequest)({
      version: "2026-11-04",
      stepId: "age",
      answer: { _tag: "Single", option: "age-25-34" },
      answeredAt: 1_700_000_000_000,
    }),
    skipped: Schema.decodeUnknownSync(SaveOnboardingAnswerRequest)({
      version: "2026-11-04",
      stepId: "cat_name",
      answer: { _tag: "Skipped" },
      answeredAt: 1_700_000_001_000,
    }),
  }),
  fixture(
    "CatEvent",
    CatEvent,
    Object.fromEntries(
      (Object.keys(catEvents) as Array<keyof typeof catEvents>).map((name) => [
        name,
        catEvent(name),
      ]),
    ),
  ),
  fixture("CatEntry", CatEntry, {
    default: catEntry(3, "game-played"),
    "note-shared": catEntry(4, "note-shared", bob),
  }),
  fixture("CatProfile", CatProfile, { default: catProfile }),
  fixture("CatTemper", CatTemper, { default: catTemper }),
  fixture("CatNeeds", CatNeeds, { default: catNeeds, missing: lonelyCatNeeds }),
  fixture("CatResponse", CatResponse, {
    default: { cat: catProfile, temper: catTemper, needs: lonelyCatNeeds, lastSeq: 4 },
    "not-adopted": {
      temper: { curious: 0.5, lazy: 0.5, cuddly: 0.5 },
      needs: { ...catNeeds, full: 0.7, rested: 0.7, loved: 0.7, playful: 0.7, mood: 0.7 },
      lastSeq: 0,
    },
  }),
  fixture("SaveCatRequest", SaveCatRequest, {
    default: Schema.decodeUnknownSync(SaveCatRequest)({
      name: "Мочи 🐾",
      look: { model: "detailed", coat: "greyWhite" },
      utcOffsetSeconds: -18_000,
    }),
  }),
  fixture("RecordCatEventRequest", RecordCatEventRequest, {
    fed: { id: idempotencyKey, event: catEvent("fed") },
    "game-played": { id: idempotencyKey, event: catEvent("game-played") },
  }),
  fixture("RecordCatEventResponse", RecordCatEventResponse, {
    default: { entry: catEntry(1, "fed"), temper: catTemper, needs: catNeeds },
  }),
  fixture("CatJournalResponse", CatJournalResponse, {
    default: { entries: [catEntry(1, "fed"), catEntry(2, "petted", bob)] },
    empty: { entries: [] },
  }),
  fixture("ActivityEvent", ActivityEvent, decodeSamples(ActivityEvent, activityEvents)),
  fixture("ActivityTarget", ActivityTarget, decodeSamples(ActivityTarget, activityTargets)),
  fixture("ActivityItem", ActivityItem, {
    default: fedItem,
    mine: drawingItem,
    "without-target": refundItem,
  }),
  fixture("ActivityResponse", ActivityResponse, {
    default: {
      items: [fedItem, drawingItem],
      next: drawingItem.cursor,
      head: fedItem.cursor,
      unread: 1,
    },
    last: { items: [refundItem], head: fedItem.cursor, unread: 0 },
    empty: { items: [], unread: 0 },
  }),
  fixture("MarkActivityReadRequest", MarkActivityReadRequest, {
    default: { upTo: activityCursor },
  }),
  fixture("ActivityUnreadResponse", ActivityUnreadResponse, { default: { unread: 3 } }),
  fixture("ClientMessage", ClientMessage, {
    resume: ClientMessage.cases.Resume.make({ lastSeq: 7 }),
    "resume-with-cat": ClientMessage.cases.Resume.make({ lastSeq: 7, lastCatSeq: 3 }),
    "resume-with-activity": ClientMessage.cases.Resume.make({
      lastSeq: 7,
      lastCatSeq: 3,
      activity: true,
    }),
    stroke: ClientMessage.cases.Stroke.make({ stroke }),
    presence: ClientMessage.cases.Presence.make({ state: "drawing" }),
    "stroke-begin": ClientMessage.cases.StrokeBegin.make({ id: 3, color: "#7B4FE0", width: 14 }),
    "stroke-points": ClientMessage.cases.StrokePoints.make({ id: 3, points: stroke.points }),
    "stroke-end": ClientMessage.cases.StrokeEnd.make({ id: 3 }),
    clear: ClientMessage.cases.Clear.make({}),
  }),
  fixture("ServerMessage", ServerMessage, {
    stroke: ServerMessage.cases.Stroke.make({ seq: 8, stroke }),
    presence: ServerMessage.cases.Presence.make({ state: "idle" }),
    "note-received": ServerMessage.cases.NoteReceived.make({ seq: 9, note: photo }),
    "text-note-received": ServerMessage.cases.NoteReceived.make({ seq: 10, note: text }),
    "photo-note-received": ServerMessage.cases.NoteReceived.make({
      seq: 11,
      note: photoWithCaption,
    }),
    "stroke-begin": ServerMessage.cases.StrokeBegin.make({ id: 3, color: "#7B4FE0", width: 14 }),
    "stroke-points": ServerMessage.cases.StrokePoints.make({ id: 3, points: stroke.points }),
    "stroke-end": ServerMessage.cases.StrokeEnd.make({ id: 3 }),
    "stroke-dropped": ServerMessage.cases.StrokeDropped.make({ id: 3 }),
    clear: ServerMessage.cases.Clear.make({}),
    "cat-entry-added": ServerMessage.cases.CatEntryAdded.make({
      entry: catEntry(5, "petted", bob),
    }),
    "cat-saved": ServerMessage.cases.CatSaved.make({ cat: catProfile }),
    "activity-unread": ServerMessage.cases.ActivityUnread.make({ unread: 2 }),
  }),
  fixture("PushPayload", PushPayload, {
    "widget-with-compact": PushPayload.cases.Widget.make({ noteId, author: alice, compact }),
    "widget-without-compact": PushPayload.cases.Widget.make({ noteId, author: bob }),
    "alert-with-compact": PushPayload.cases.Alert.make({ noteId, author: alice, compact }),
    "alert-without-compact": PushPayload.cases.Alert.make({ noteId, author: bob }),
    "widget-text": PushPayload.cases.Widget.make({
      noteId,
      author: bob,
      text: "miss you already 💛",
      paper: "butter",
    }),
    "alert-text": PushPayload.cases.Alert.make({ noteId, author: alice, text: "home soon" }),
    "live-activity": PushPayload.cases.LiveActivity.make({ noteId, author: alice, compact }),
    "live-activity-on-paper": PushPayload.cases.LiveActivity.make({
      noteId,
      author: bob,
      compact,
      paper: "sky",
    }),
  }),
];
