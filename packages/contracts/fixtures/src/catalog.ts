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
import { ApiError } from "@billet/contracts-http-api/api-error";
import {
  AuthChallengeResponse,
  AuthNonce,
  IdentityToken,
  SessionResponse,
  SessionToken,
  SignInWithAppleRequest,
} from "@billet/contracts-http-api/auth";
import { RegisterPushTokenRequest } from "@billet/contracts-http-api/device";
import { FlagsResponse } from "@billet/contracts-http-api/flags";
import {
  ClaimInviteRequest,
  ClaimInviteResponse,
  CreateInviteResponse,
} from "@billet/contracts-http-api/invite";
import {
  ListNotesResponse,
  SendNoteRequest,
  SendNoteResponse,
  UploadImageResponse,
} from "@billet/contracts-http-api/note";
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
const photo = Note.cases.Photo.make({ id: noteId, author: bob, sentAt: 1_700_000_001_000, image });

export const catalog: ReadonlyArray<Fixture> = [
  fixture("PairId", PairId, { default: pairId }),
  fixture("CompactStrokes", CompactStrokes, { default: compact }),
  fixture("Stroke", Stroke, { default: stroke }),
  fixture("Note", Note, { drawing, photo }),
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
    photo: SendNoteRequest.cases.Photo.make({ key: idempotencyKey, image }),
  }),
  fixture("SendNoteResponse", SendNoteResponse, { default: { note: drawing } }),
  fixture("FlagsResponse", FlagsResponse, {
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
      ],
    },
  }),
  fixture("AuthChallengeResponse", AuthChallengeResponse, {
    default: { nonce, expiresAt: 1_700_000_300_000 },
  }),
  fixture("SignInWithAppleRequest", SignInWithAppleRequest, { default: { identityToken } }),
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
  }),
  fixture("PushPayload", PushPayload, {
    "widget-with-compact": PushPayload.cases.Widget.make({ noteId, author: alice, compact }),
    "widget-without-compact": PushPayload.cases.Widget.make({ noteId, author: bob }),
    "alert-with-compact": PushPayload.cases.Alert.make({ noteId, author: alice, compact }),
    "alert-without-compact": PushPayload.cases.Alert.make({ noteId, author: bob }),
  }),
];
