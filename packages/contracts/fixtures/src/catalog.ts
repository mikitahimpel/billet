import { Schema } from "effect";
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
  StampsResponse,
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
const text = Note.cases.Text.make({
  id: noteId,
  author: bob,
  sentAt: 1_700_000_002_000,
  text: "miss you already 💛",
  paper: "butter",
});
const plainText = Note.cases.Text.make({
  id: noteId,
  author: alice,
  sentAt: 1_700_000_003_000,
  text: "home soon",
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
    }),
    "text-without-paper": SendNoteRequest.cases.Text.make({
      key: idempotencyKey,
      text: "home soon",
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
  }),
  // A JWS's shape only: never signed by anyone.
  fixture("PurchaseRequest", PurchaseRequest, {
    default: {
      signedTransaction: "eyJhbGciOiJFUzI1NiJ9.eyJ0cmFuc2FjdGlvbklkIjoiMSJ9.c2lnbmF0dXJl",
    },
  }),
  fixture("MockPurchaseRequest", MockPurchaseRequest, {
    purchase: {
      productId: "com.mikitahimpel.billet.stamps.100",
      transactionId: "mock-6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f",
      kind: "purchase",
    },
    refund: {
      productId: "com.mikitahimpel.billet.stamps.100",
      transactionId: "mock-6f1c2d3e-4a5b-4c6d-8e7f-0a1b2c3d4e5f",
      kind: "refund",
    },
  }),
  fixture("PurchaseResponse", PurchaseResponse, {
    default: {
      transactionId: "2000000812345678",
      productId: "com.mikitahimpel.billet.stamps.550",
      stamps: 550,
      balance: 1234,
      duplicate: false,
    },
    duplicate: {
      transactionId: "2000000812345678",
      productId: "com.mikitahimpel.billet.stamps.550",
      stamps: 550,
      balance: 1234,
      duplicate: true,
    },
  }),
  fixture("StampsResponse", StampsResponse, {
    default: {
      balance: 550,
      entries: [
        {
          id: "purchase:2000000812345678",
          kind: "purchase",
          amount: 100,
          productId: "com.mikitahimpel.billet.stamps.100",
          at: "2026-11-04T15:00:00.000Z",
        },
        {
          id: "purchase:2000000812345679",
          kind: "purchase",
          amount: 550,
          productId: "com.mikitahimpel.billet.stamps.550",
          at: "2026-11-04T15:05:00.000Z",
        },
        {
          id: "refund:2000000812345678",
          kind: "refund",
          amount: -100,
          productId: "com.mikitahimpel.billet.stamps.100",
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
  fixture("ClientMessage", ClientMessage, {
    resume: ClientMessage.cases.Resume.make({ lastSeq: 7 }),
    stroke: ClientMessage.cases.Stroke.make({ stroke }),
    presence: ClientMessage.cases.Presence.make({ state: "drawing" }),
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
  }),
];
