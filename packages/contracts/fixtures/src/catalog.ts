import { Schema } from "effect";
import { DeliveryLane } from "@billet/contracts-domain/delivery-lane";
import { InviteCode, MediaKey, NoteId, UserId } from "@billet/contracts-domain/ids";
import { CompactStrokes, Stroke } from "@billet/contracts-domain/ink";
import { Note } from "@billet/contracts-domain/note";
import { PairId } from "@billet/contracts-domain/pair-id";
import { ApiError } from "@billet/contracts-http-api/api-error";
import {
  ClaimInviteRequest,
  ClaimInviteResponse,
  CreateInviteResponse,
} from "@billet/contracts-http-api/invite";
import {
  ListNotesResponse,
  SendNoteRequest,
  SendNoteResponse,
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
const code = Schema.decodeUnknownSync(InviteCode)("INVITE-1");

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
  fixture("CreateInviteResponse", CreateInviteResponse, { default: { code } }),
  fixture("ClaimInviteRequest", ClaimInviteRequest, { default: { code } }),
  fixture("ClaimInviteResponse", ClaimInviteResponse, { default: { pairId } }),
  fixture("SendNoteRequest", SendNoteRequest, {
    drawing: SendNoteRequest.cases.Drawing.make({ compact, image }),
    photo: SendNoteRequest.cases.Photo.make({ image }),
  }),
  fixture("SendNoteResponse", SendNoteResponse, { default: { note: drawing } }),
  fixture("ListNotesResponse", ListNotesResponse, { default: { notes: [drawing, photo] } }),
  fixture("ApiError", ApiError, {
    unauthorized: ApiError.cases.Unauthorized.make({}),
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
