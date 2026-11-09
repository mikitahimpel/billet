import { MAX_DAILY_INK } from "./daily-drawing.ts";

export const MAX_QUEUED_PETS = 10;
export const MAX_TREAT_DAYS = 90;
export const MAX_REACTIONS = 200;
export const MAX_NAME_LENGTH = 24;
export const MAX_LIFE_EVENTS = 400;
export const MAX_QUEUED_GIFTS = 20;
export const MAX_GIFT_MESSAGE = 80;

/** A shoo sends the cat off where it sat, so it learns to stay off. */
export type LifePlayKind = "feed" | "play" | "sleep" | "shoo";
export type PlayKind =
  | "pet"
  | "treat"
  | LifePlayKind
  | "name"
  | "rename"
  | "react"
  | "adopt"
  | "light"
  | "style"
  | "arrange"
  | "daily"
  | "gift"
  | "gift-opened";
export type Reaction = "heart" | "stamp";

export interface PlayFrame {
  readonly id: string;
  readonly kind: "pet" | "treat" | LifePlayKind;
  readonly at: string;
}

/** The ID is that of the frame that carried the event. */
export interface LifeEvent {
  readonly id: string;
  readonly kind: "feed" | "pet" | "play" | "note" | "sleep" | "shoo";
  readonly by: string;
  readonly at: string;
}

export interface NameFrame {
  readonly id: string;
  readonly kind: "name";
  readonly at: string;
  readonly name: string;
}

export interface ReactFrame {
  readonly id: string;
  readonly kind: "react";
  readonly at: string;
  readonly note: string;
  readonly reaction: Reaction;
}

/** The last name given wins. */
export interface RenameFrame {
  readonly id: string;
  readonly kind: "rename";
  readonly at: string;
  readonly name: string;
}

export const ROOM_LIGHTS = ["on", "cosy", "off"] as const;
export type RoomLight = (typeof ROOM_LIGHTS)[number];

/** The last press from either phone wins. */
export interface LightFrame {
  readonly id: string;
  readonly kind: "light";
  readonly at: string;
  readonly light: RoomLight;
}

/** The room keeps any name it is sent; a phone reads an unknown one as the standard look. */
export const ROOM_STYLE_PARTS = ["wall", "floor", "curtains", "drape", "view", "fairy"] as const;
export type RoomStylePart = (typeof ROOM_STYLE_PARTS)[number];
export type RoomStyle = Readonly<Partial<Record<RoomStylePart, string>>>;

/** The last style from either phone wins, whole. */
export interface StyleFrame {
  readonly id: string;
  readonly kind: "style";
  readonly at: string;
  readonly style: RoomStyle;
}

const STYLE_NAME = /^[A-Za-z]{1,32}$/;

export const parseStyle = (value: unknown): RoomStyle | undefined => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return undefined;
  const style: Partial<Record<RoomStylePart, string>> = {};
  for (const [key, name] of Object.entries(value)) {
    if (!(ROOM_STYLE_PARTS as readonly string[]).includes(key)) return undefined;
    if (typeof name !== "string" || !STYLE_NAME.test(name)) return undefined;
    style[key as RoomStylePart] = name;
  }
  return style;
};

export const MAX_ARRANGED_PIECES = 80;
/** Room units from the room's middle. */
export const MAX_ARRANGED_REACH = 20;

/** Yaw in radians. */
export type PieceSpot = readonly [x: number, z: number, yaw: number];

/** A piece missing from `spots` stands where the room first put it. Last arrangement wins. */
export interface ArrangeFrame {
  readonly id: string;
  readonly kind: "arrange";
  readonly at: string;
  readonly room: string;
  readonly spots: Readonly<Record<string, PieceSpot>>;
}

export const ADOPTION_CATS = ["ginger", "greyWhite", "black", "kitten", "fluffy"] as const;
export type AdoptionCat = (typeof ADOPTION_CATS)[number];

export type AdoptMove =
  | { readonly move: "pick"; readonly cat: AdoptionCat | null }
  | { readonly move: "hold"; readonly holding: boolean }
  | { readonly move: "adopt"; readonly cat: AdoptionCat };

export type AdoptFrame = {
  readonly id: string;
  readonly kind: "adopt";
  readonly at: string;
} & AdoptMove;

/** The day is the one `at` was written on. */
export interface DailyFrame {
  readonly id: string;
  readonly kind: "daily";
  readonly at: string;
  readonly ink: string;
}

/** The room only passes it on: the item is a shop id, the note the sender's own words. */
export interface GiftFrame {
  readonly id: string;
  readonly kind: "gift";
  readonly at: string;
  readonly item: string;
  readonly message?: string;
}

export interface GiftOpenedFrame {
  readonly id: string;
  readonly kind: "gift-opened";
  readonly at: string;
  readonly gift: string;
}

export type AnyPlayFrame =
  | PlayFrame
  | NameFrame
  | RenameFrame
  | ReactFrame
  | AdoptFrame
  | LightFrame
  | StyleFrame
  | ArrangeFrame
  | DailyFrame
  | GiftFrame
  | GiftOpenedFrame;

const isRoomLight = (value: unknown): value is RoomLight =>
  typeof value === "string" && (ROOM_LIGHTS as readonly string[]).includes(value);

const ARRANGE_NAME = /^[A-Za-z0-9._-]{1,64}$/;

const isReach = (value: unknown): value is number =>
  typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= MAX_ARRANGED_REACH;

export const parseArrangement = (
  room: unknown,
  spots: unknown,
): { room: string; spots: Record<string, PieceSpot> } | undefined => {
  if (typeof room !== "string" || !ARRANGE_NAME.test(room)) return undefined;
  if (typeof spots !== "object" || spots === null || Array.isArray(spots)) return undefined;
  const entries = Object.entries(spots);
  if (entries.length > MAX_ARRANGED_PIECES) return undefined;
  const parsed: Record<string, PieceSpot> = {};
  for (const [name, spot] of entries) {
    if (!ARRANGE_NAME.test(name) || !Array.isArray(spot) || spot.length !== 3) return undefined;
    const [x, z, yaw] = spot as unknown[];
    if (!isReach(x) || !isReach(z) || !isReach(yaw)) return undefined;
    parsed[name] = [x, z, yaw];
  }
  return { room, spots: parsed };
};

export type Reactions = Readonly<Record<string, Reaction>>;

/** Calendar day (`YYYY-MM-DD`) to the devices that gave a treat that day. */
export type TreatDays = Readonly<Record<string, readonly string[]>>;

export type QueuedGift = (GiftFrame | GiftOpenedFrame) & {
  readonly from: string;
  readonly to: string;
};

export const giftFrame = (gift: QueuedGift): Readonly<Record<string, unknown>> =>
  gift.kind === "gift"
    ? {
        type: "gift",
        id: gift.id,
        item: gift.item,
        ...(gift.message === undefined ? {} : { message: gift.message }),
      }
    : { type: "gift-opened", id: gift.gift };

const SHOP_ID = /^[A-Za-z0-9._-]{1,64}$/;

/** Trimmed, one to `MAX_GIFT_MESSAGE` characters, no control characters; null when invalid. */
export const parseGiftMessage = (value: unknown): string | undefined | null => {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") return null;
  const message = value.trim();
  if (message.length === 0) return undefined;
  if ([...message].length > MAX_GIFT_MESSAGE || /\p{Cc}/u.test(message)) return null;
  return message;
};

export interface QueuedPet extends PlayFrame {
  readonly kind: "pet";
  readonly from: string;
  readonly to: string;
}

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const ISO_TIME = /^(\d{4}-\d{2}-\d{2})T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})$/;

export const isTime = (at: unknown): at is string =>
  typeof at === "string" && ISO_TIME.test(at) && !Number.isNaN(Date.parse(at));

/** Trimmed, one to `MAX_NAME_LENGTH` characters, no control characters. */
export const parseName = (value: unknown): string | undefined => {
  if (typeof value !== "string") return undefined;
  const name = value.trim();
  const length = [...name].length;
  if (length < 1 || length > MAX_NAME_LENGTH || /\p{Cc}/u.test(name)) return undefined;
  return name;
};

export const parsePlay = (frame: Readonly<Record<string, unknown>>): AnyPlayFrame | undefined => {
  const { id, kind, at } = frame;
  if (typeof id !== "string" || !UUID.test(id)) return undefined;
  if (!isTime(at)) return undefined;
  switch (kind) {
    case "pet":
    case "treat":
    case "feed":
    case "play":
    case "sleep":
    case "shoo":
      return { id, kind, at };
    case "name":
    case "rename": {
      const name = parseName(frame["name"]);
      return name === undefined ? undefined : { id, kind, at, name };
    }
    case "adopt":
      return parseAdopt(id, at, frame);
    case "light": {
      const { light } = frame;
      return isRoomLight(light) ? { id, kind, at, light } : undefined;
    }
    case "style": {
      const style = parseStyle(frame["style"]);
      return style ? { id, kind, at, style } : undefined;
    }
    case "arrange": {
      const arrangement = parseArrangement(frame["room"], frame["spots"]);
      return arrangement === undefined ? undefined : { id, kind, at, ...arrangement };
    }
    case "daily": {
      const { ink } = frame;
      if (typeof ink !== "string" || ink.length === 0 || ink.length > MAX_DAILY_INK) {
        return undefined;
      }
      return { id, kind, at, ink };
    }
    case "gift": {
      const { item } = frame;
      if (typeof item !== "string" || !SHOP_ID.test(item)) return undefined;
      const message = parseGiftMessage(frame["message"]);
      if (message === null) return undefined;
      return message === undefined
        ? { id: id.toLowerCase(), kind, at, item }
        : { id: id.toLowerCase(), kind, at, item, message };
    }
    case "gift-opened": {
      const { gift } = frame;
      if (typeof gift !== "string" || !UUID.test(gift)) return undefined;
      return { id, kind, at, gift: gift.toLowerCase() };
    }
    case "react": {
      const { note, reaction } = frame;
      if (typeof note !== "string" || !UUID.test(note)) return undefined;
      if (reaction !== "heart" && reaction !== "stamp") return undefined;
      return { id, kind, at, note: note.toLowerCase(), reaction };
    }
    default:
      return undefined;
  }
};

const isAdoptionCat = (value: unknown): value is AdoptionCat =>
  typeof value === "string" && (ADOPTION_CATS as readonly string[]).includes(value);

const parseAdopt = (
  id: string,
  at: string,
  frame: Readonly<Record<string, unknown>>,
): AdoptFrame | undefined => {
  const { move, cat, holding } = frame;
  switch (move) {
    case "pick":
      if (cat === undefined || cat === null) return { id, kind: "adopt", at, move, cat: null };
      return isAdoptionCat(cat) ? { id, kind: "adopt", at, move, cat } : undefined;
    case "hold":
      return typeof holding === "boolean" ? { id, kind: "adopt", at, move, holding } : undefined;
    case "adopt":
      return isAdoptionCat(cat) ? { id, kind: "adopt", at, move, cat } : undefined;
    default:
      return undefined;
  }
};

export const adoptFrame = (play: AdoptFrame): Readonly<Record<string, unknown>> => {
  switch (play.move) {
    case "pick":
    case "adopt":
      return { type: "adopt", id: play.id, move: play.move, cat: play.cat };
    case "hold":
      return {
        type: "adopt",
        id: play.id,
        move: play.move,
        holding: play.holding,
      };
  }
};

/** The cat keeps the first name it was given. */
export const keepFirstName = (current: string | undefined, proposed: string): string =>
  current ?? proposed;

/** Replaces an earlier reaction to `note`; the newest `MAX_REACTIONS` notes stay. */
export const recordReaction = (
  reactions: Reactions,
  note: string,
  reaction: Reaction,
): Reactions => {
  const { [note]: _replaced, ...others } = reactions;
  const keep = Object.entries({ ...others, [note]: reaction }).slice(-MAX_REACTIONS);
  return Object.fromEntries(keep);
};

/** The sender's local calendar day, from the offset-carrying timestamp as written. */
export const dayOf = (at: string): string => at.slice(0, 10);

/** One treat per device per day; the newest `MAX_TREAT_DAYS` days are kept. */
export const recordTreat = (days: TreatDays, device: string, at: string): TreatDays => {
  const day = dayOf(at);
  const given = days[day] ?? [];
  if (given.includes(device)) return days;
  const next = { ...days, [day]: [...given, device] };
  const keep = Object.keys(next).sort().slice(-MAX_TREAT_DAYS);
  return Object.fromEntries(keep.map((d) => [d, next[d] ?? []]));
};

/** Returns `log` itself for a repeat ID, so the caller can tell whether to broadcast. */
export const recordLife = (log: readonly LifeEvent[], event: LifeEvent): readonly LifeEvent[] => {
  if (log.some((e) => e.id === event.id)) return log;
  const next = [...log, event].sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
  return next.slice(-MAX_LIFE_EVENTS);
};
