// The push lanes of the PairRoom's delivery ledger: which lanes a room hands notes to, and how one
// try of one lane goes. Pure over its dependencies, so the room and the tests supply them.
import type { DeliveryEntry, DeliveryOutcome } from "@billet/backend-pair-room/delivery-ledger";
import type { Note } from "@billet/contracts-domain/note";
import type { ApnsEnvironment, ApnsPush, ApnsPushType, ApnsResult } from "./apns-client.ts";
import {
  alertBody,
  byteLength,
  liveActivityBody,
  maxPushBytes,
  widgetBody,
} from "./apns-payloads.ts";

/** The token kind and APNs push type behind each push lane. */
export const pushLanes = {
  WidgetPush: { kind: "widget", pushType: "widgets" },
  AlertPush: { kind: "alert", pushType: "alert" },
  LiveActivityPush: { kind: "liveactivity", pushType: "liveactivity" },
} as const satisfies Record<string, { readonly kind: string; readonly pushType: ApnsPushType }>;

export type PushLane = keyof typeof pushLanes;

export interface PushLaneSettings {
  readonly APNS_KEY?: string;
  readonly APNS_KEY_ID?: string;
  /** `on` adds the Live Activity lane. Anything else, or absent, leaves it off. */
  readonly LIVE_ACTIVITY_PUSH?: string;
}

/**
 * The lanes a room uses: none without an APNs key, the widget and alert lanes with one, and the
 * Live Activity lane only when `LIVE_ACTIVITY_PUSH` is `on`.
 */
export const enabledPushLanes = (settings: PushLaneSettings): ReadonlyArray<PushLane> => {
  if (!settings.APNS_KEY || !settings.APNS_KEY_ID) return [];
  return settings.LIVE_ACTIVITY_PUSH === "on"
    ? ["WidgetPush", "AlertPush", "LiveActivityPush"]
    : ["WidgetPush", "AlertPush"];
};

export interface DeviceToken {
  readonly token: string;
  readonly environment: ApnsEnvironment;
}

export interface PushLaneDependencies {
  /** The stored note the entry is for, if the room still has it. */
  readonly note: (noteId: string) => Promise<Note | undefined>;
  /** Who receives it: the member who did not write it. */
  readonly recipient: (note: Note) => Promise<string | undefined>;
  readonly tokens: (user: string, kind: string) => Promise<ReadonlyArray<DeviceToken>>;
  readonly dropToken: (token: string, kind: string) => Promise<void>;
  readonly send: (push: ApnsPush) => Promise<ApnsResult>;
  readonly nowSeconds: () => number;
}

const bodyFor = (lane: PushLane, note: Note, nowSeconds: number): unknown => {
  switch (lane) {
    case "AlertPush":
      return alertBody(note);
    case "WidgetPush":
      return widgetBody(note);
    case "LiveActivityPush":
      return liveActivityBody(note, nowSeconds);
  }
};

const isPushLane = (lane: string): lane is PushLane => Object.hasOwn(pushLanes, lane);

/**
 * One try of one lane: sends the note to every device of the partner that has a token for it.
 * Delivered once any device took it; Retry while any failure may pass; Abandon when there is no
 * one to send to or nothing will ever be accepted. A dead token is dropped as it is found. A lane
 * that does not apply to the note (a Live Activity for a photo) counts as done.
 */
export const sendPushLane = async (
  entry: Pick<DeliveryEntry, "noteId" | "lane">,
  deps: PushLaneDependencies,
): Promise<DeliveryOutcome> => {
  if (!isPushLane(entry.lane)) return "Abandon";
  const { kind, pushType } = pushLanes[entry.lane];
  const note = await deps.note(entry.noteId);
  if (note === undefined) return "Abandon";
  const body = bodyFor(entry.lane, note, deps.nowSeconds());
  if (body === undefined) return "Delivered";
  if (byteLength(body) > maxPushBytes) return "Abandon";
  const recipient = await deps.recipient(note);
  if (recipient === undefined) return "Abandon";
  const tokens = await deps.tokens(recipient, kind);
  if (tokens.length === 0) return "Abandon";

  const results = await Promise.all(
    tokens.map(async ({ token, environment }) => {
      const result = await deps.send({ token, environment, pushType, body, collapseId: note.id });
      if (result._tag === "Unregistered") await deps.dropToken(token, kind);
      return result;
    }),
  );
  if (results.some((result) => result._tag === "Delivered")) return "Delivered";
  if (results.some((result) => result._tag === "Retry")) return "Retry";
  return "Abandon";
};
