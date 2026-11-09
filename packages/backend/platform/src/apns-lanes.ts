// Pure over its dependencies, so the room and the tests supply them.
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
  riddleAlertBody,
  riddleEndedAlertBody,
  reactionAlertBody,
  widgetBody,
} from "./apns-payloads.ts";

export const pushLanes = {
  WidgetPush: { kind: "widget", pushType: "widgets" },
  AlertPush: { kind: "alert", pushType: "alert" },
  LiveActivityPush: { kind: "liveactivity", pushType: "liveactivity" },
} as const satisfies Record<string, { readonly kind: string; readonly pushType: ApnsPushType }>;

export type PushLane = keyof typeof pushLanes;

export interface PushLaneSettings {
  readonly APNS_KEY?: string;
  readonly APNS_KEY_ID?: string;
  /** Only `on` adds the Live Activity lane. */
  readonly LIVE_ACTIVITY_PUSH?: string;
}

/** No lanes without an APNs key; Live Activity only when `LIVE_ACTIVITY_PUSH` is `on`. */
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
  readonly note: (noteId: string) => Promise<Note | undefined>;
  /** Only while the change under `rev` is still the latest. */
  readonly reaction: (
    rev: number,
  ) => Promise<{ readonly reaction: NoteReaction; readonly note: Note } | undefined>;
  /** Only while both members still want the Pick tonight match. */
  readonly match: (
    key: string,
    at: number,
  ) => Promise<{ readonly recipient: string; readonly name: string } | undefined>;
  /** Only while the round still waits for the partner. */
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
  readonly riddle: (id: string) => Promise<
    | {
        readonly drawer: string;
        readonly guesser: string;
        readonly word: string;
        readonly tries: number;
        readonly state: "Open" | "Solved" | "GivenUp";
      }
    | undefined
  >;
  /** The member who did not write the note. */
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

/** Shares the ledger key space with note ids. */
export const reactionDeliveryId = (rev: number): string => `${reactionPrefix}${rev}`;

const reactionRevOf = (deliveryId: string): number | undefined => {
  if (!deliveryId.startsWith(reactionPrefix)) return undefined;
  const rev = Number(deliveryId.slice(reactionPrefix.length));
  return Number.isInteger(rev) ? rev : undefined;
};

const matchPrefix = "match:";

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

const riddlePrefix = "riddle:";
const riddleEndPrefix = "riddle-end:";

export const riddleDeliveryId = (id: string): string => `${riddlePrefix}${id}`;

export const riddleEndDeliveryId = (id: string): string => `${riddleEndPrefix}${id}`;

const riddleOfDelivery = (
  deliveryId: string,
): { readonly id: string; readonly ended: boolean } | undefined => {
  if (deliveryId.startsWith(riddlePrefix)) {
    return { id: deliveryId.slice(riddlePrefix.length), ended: false };
  }
  if (deliveryId.startsWith(riddleEndPrefix)) {
    return { id: deliveryId.slice(riddleEndPrefix.length), ended: true };
  }
  return undefined;
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
      if (result._tag === "Unregistered") {
        // A failed delete must not lose the other devices' results; the next dead answer drops it.
        await deps.dropToken(token, kind).catch(() => undefined);
      }
      return result;
    }),
  );
  if (results.some((result) => result._tag === "Delivered")) return "Delivered";
  if (results.some((result) => result._tag === "Retry")) return "Retry";
  return "Abandon";
};

/** Alert lane only; a reaction changed since is skipped, as the change has its own delivery. */
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

/** Alert lane only, to the partner who swiped first. */
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

/** Alert lane only; not sent once the round revealed or closed. */
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

/** Alert lane only: a new riddle to its guesser while open, an ended one to its drawer. */
const sendRiddleLane = async (
  lane: PushLane,
  delivery: { readonly id: string; readonly ended: boolean },
  deps: PushLaneDependencies,
): Promise<DeliveryOutcome> => {
  if (lane !== "AlertPush") return "Delivered";
  const found = await deps.riddle(delivery.id);
  if (found === undefined || (found.state === "Open") === delivery.ended) return "Abandon";
  switch (found.state) {
    case "Open": {
      const body = riddleAlertBody(found.word.replaceAll(" ", "").length);
      return sendToAll(found.guesser, lane, body, `d-${delivery.id}`, deps);
    }
    case "Solved":
    case "GivenUp": {
      const body = riddleEndedAlertBody(found.word, found.state === "Solved", found.tries);
      return sendToAll(found.drawer, lane, body, `de-${delivery.id}`, deps);
    }
  }
};

/** Abandon when there is no one to send to or nothing will be accepted; n/a lanes count as done. */
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
  const riddle = riddleOfDelivery(entry.noteId);
  if (riddle !== undefined) return sendRiddleLane(entry.lane, riddle, deps);
  const note = await deps.note(entry.noteId);
  if (note === undefined) return "Abandon";
  const body = bodyFor(entry.lane, note, deps.nowSeconds());
  if (body === undefined) return "Delivered";
  if (byteLength(body) > maxPushBytes) return "Abandon";
  const recipient = await deps.recipient(note);
  if (recipient === undefined) return "Abandon";
  return sendToAll(recipient, entry.lane, body, note.id, deps);
};
