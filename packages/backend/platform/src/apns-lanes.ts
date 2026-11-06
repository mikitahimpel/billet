// The push lanes of the PairRoom's delivery ledger: which lanes a room hands notes to, and how one
// try of one lane goes. Pure over its dependencies, so the room and the tests supply them.
import type { DeliveryEntry, DeliveryOutcome } from "@billet/backend-pair-room/delivery-ledger";
import type { Note } from "@billet/contracts-domain/note";
import type { NoteReaction } from "@billet/contracts-domain/reaction";
import type { ApnsEnvironment, ApnsPush, ApnsPushType, ApnsResult } from "./apns-client.ts";
import {
  alertBody,
  byteLength,
  guessAlertBody,
  liveActivityBody,
  matchAlertBody,
  maxPushBytes,
  reactionAlertBody,
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
  /** The reaction change under its `rev` and the note it is on, while it is the latest. */
  readonly reaction: (
    rev: number,
  ) => Promise<{ readonly reaction: NoteReaction; readonly note: Note } | undefined>;
  /**
   * The Pick tonight match the card `key` made at `at`, while both still want it: whom to tell and
   * the card's name.
   */
  readonly match: (
    key: string,
    at: number,
  ) => Promise<{ readonly recipient: string; readonly name: string } | undefined>;
  /**
   * Whom to tell that `member` finished their part of the Who knows who round of `day`, while the
   * round still waits for the partner, with the part they played and the round's length.
   */
  readonly guess: (
    day: string,
    member: string,
  ) => Promise<
    | {
        readonly recipient: string;
        readonly role: "subject" | "guesser";
        readonly count: number;
      }
    | undefined
  >;
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

const reactionPrefix = "reaction:";

/** The ledger key of a reaction change's delivery, beside the note ids of note deliveries. */
export const reactionDeliveryId = (rev: number): string => `${reactionPrefix}${rev}`;

const reactionRevOf = (deliveryId: string): number | undefined => {
  if (!deliveryId.startsWith(reactionPrefix)) return undefined;
  const rev = Number(deliveryId.slice(reactionPrefix.length));
  return Number.isInteger(rev) ? rev : undefined;
};

const matchPrefix = "match:";

/** The ledger key of a Pick tonight match's delivery: the card and when the match was made. */
export const matchDeliveryId = (key: string, at: number): string => `${matchPrefix}${at}:${key}`;

const matchOfDelivery = (
  deliveryId: string,
): { readonly key: string; readonly at: number } | undefined => {
  if (!deliveryId.startsWith(matchPrefix)) return undefined;
  const rest = deliveryId.slice(matchPrefix.length);
  const colon = rest.indexOf(":");
  const at = Number(rest.slice(0, colon));
  return colon > 0 && Number.isInteger(at) ? { key: rest.slice(colon + 1), at } : undefined;
};

const guessPrefix = "guess:";

/** The ledger key of the push that `member` finished their part of the round of `day`. */
export const guessDeliveryId = (day: string, member: string): string =>
  `${guessPrefix}${day}:${member}`;

const guessOfDelivery = (
  deliveryId: string,
): { readonly day: string; readonly member: string } | undefined => {
  if (!deliveryId.startsWith(guessPrefix)) return undefined;
  const rest = deliveryId.slice(guessPrefix.length);
  const colon = rest.indexOf(":");
  return colon > 0 ? { day: rest.slice(0, colon), member: rest.slice(colon + 1) } : undefined;
};

const sendToAll = async (
  recipient: string,
  lane: PushLane,
  body: unknown,
  collapseId: string,
  deps: PushLaneDependencies,
): Promise<DeliveryOutcome> => {
  const { kind, pushType } = pushLanes[lane];
  const tokens = await deps.tokens(recipient, kind);
  if (tokens.length === 0) return "Abandon";
  const results = await Promise.all(
    tokens.map(async ({ token, environment }) => {
      const result = await deps.send({ token, environment, pushType, body, collapseId });
      if (result._tag === "Unregistered") await deps.dropToken(token, kind);
      return result;
    }),
  );
  if (results.some((result) => result._tag === "Delivered")) return "Delivered";
  if (results.some((result) => result._tag === "Retry")) return "Retry";
  return "Abandon";
};

/**
 * A reaction is an alert to the photo's author, and nothing on the other lanes. One that was
 * changed or taken back since is not sent: the change after it has its own delivery.
 */
const sendReactionLane = async (
  lane: PushLane,
  rev: number,
  deps: PushLaneDependencies,
): Promise<DeliveryOutcome> => {
  if (lane !== "AlertPush") return "Delivered";
  const found = await deps.reaction(rev);
  if (found === undefined) return "Abandon";
  const { reaction, note } = found;
  if (reaction.reaction === undefined) return "Delivered";
  const body = reactionAlertBody({
    note: reaction.note,
    by: reaction.by,
    reaction: reaction.reaction,
  });
  return sendToAll(note.author, lane, body, `r-${note.id}`, deps);
};

/** A match is an alert to the partner who swiped first, and nothing on the other lanes. */
const sendMatchLane = async (
  lane: PushLane,
  match: { readonly key: string; readonly at: number },
  deps: PushLaneDependencies,
): Promise<DeliveryOutcome> => {
  if (lane !== "AlertPush") return "Delivered";
  const found = await deps.match(match.key, match.at);
  if (found === undefined) return "Abandon";
  return sendToAll(found.recipient, lane, matchAlertBody(found.name), `m-${match.key}`, deps);
};

/**
 * A finished part is an alert to the partner, and nothing on the other lanes. One whose round
 * revealed or closed since is not sent.
 */
const sendGuessLane = async (
  lane: PushLane,
  part: { readonly day: string; readonly member: string },
  deps: PushLaneDependencies,
): Promise<DeliveryOutcome> => {
  if (lane !== "AlertPush") return "Delivered";
  const found = await deps.guess(part.day, part.member);
  if (found === undefined) return "Abandon";
  const body = guessAlertBody(found.role, found.count);
  return sendToAll(found.recipient, lane, body, `g-${part.day}`, deps);
};

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
  const rev = reactionRevOf(entry.noteId);
  if (rev !== undefined) return sendReactionLane(entry.lane, rev, deps);
  const match = matchOfDelivery(entry.noteId);
  if (match !== undefined) return sendMatchLane(entry.lane, match, deps);
  const part = guessOfDelivery(entry.noteId);
  if (part !== undefined) return sendGuessLane(entry.lane, part, deps);
  const note = await deps.note(entry.noteId);
  if (note === undefined) return "Abandon";
  const body = bodyFor(entry.lane, note, deps.nowSeconds());
  if (body === undefined) return "Delivered";
  if (byteLength(body) > maxPushBytes) return "Abandon";
  const recipient = await deps.recipient(note);
  if (recipient === undefined) return "Abandon";
  return sendToAll(recipient, entry.lane, body, note.id, deps);
};
