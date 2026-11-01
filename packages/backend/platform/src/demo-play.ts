// Play frames for the demo room: petting the cat, giving the day's treat, naming the cat and
// reacting to a note.

export const MAX_QUEUED_PETS = 10;
export const MAX_TREAT_DAYS = 90;
export const MAX_REACTIONS = 200;
export const MAX_NAME_LENGTH = 24;

export type PlayKind = "pet" | "treat" | "name" | "react";
export type Reaction = "heart" | "stamp";

/** A pet or a treat: nothing but who did it and when. */
export interface PlayFrame {
  readonly id: string;
  readonly kind: "pet" | "treat";
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
  /** The note being reacted to. */
  readonly note: string;
  readonly reaction: Reaction;
}

export type AnyPlayFrame = PlayFrame | NameFrame | ReactFrame;

/** Note id mapped to the reaction its receiver gave it. */
export type Reactions = Readonly<Record<string, Reaction>>;

/** Calendar day (`YYYY-MM-DD`) mapped to the devices that gave a treat that day. */
export type TreatDays = Readonly<Record<string, readonly string[]>>;

export interface QueuedPet extends PlayFrame {
  readonly from: string;
  readonly to: string;
}

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const ISO_TIME = /^(\d{4}-\d{2}-\d{2})T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})$/;

/** A name as shown: trimmed, one to `MAX_NAME_LENGTH` characters, no control characters. */
export const parseName = (value: unknown): string | undefined => {
  if (typeof value !== "string") return undefined;
  const name = value.trim();
  const length = [...name].length;
  if (length < 1 || length > MAX_NAME_LENGTH || /\p{Cc}/u.test(name)) return undefined;
  return name;
};

/** Reads a `play` frame, or returns undefined when any field is missing or malformed. */
export const parsePlay = (frame: Readonly<Record<string, unknown>>): AnyPlayFrame | undefined => {
  const { id, kind, at } = frame;
  if (typeof id !== "string" || !UUID.test(id)) return undefined;
  if (typeof at !== "string" || !ISO_TIME.test(at) || Number.isNaN(Date.parse(at))) {
    return undefined;
  }
  switch (kind) {
    case "pet":
    case "treat":
      return { id, kind, at };
    case "name": {
      const name = parseName(frame["name"]);
      return name === undefined ? undefined : { id, kind, at, name };
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

/** The cat keeps the first name it was given; a later one changes nothing. */
export const keepFirstName = (current: string | undefined, proposed: string): string =>
  current ?? proposed;

/** Sets the reaction to `note`, replacing an earlier one; the newest `MAX_REACTIONS` notes stay. */
export const recordReaction = (
  reactions: Reactions,
  note: string,
  reaction: Reaction,
): Reactions => {
  const { [note]: _replaced, ...others } = reactions;
  const keep = Object.entries({ ...others, [note]: reaction }).slice(-MAX_REACTIONS);
  return Object.fromEntries(keep);
};

/** The sender's local calendar day, taken from the offset-carrying timestamp as written. */
export const dayOf = (at: string): string => at.slice(0, 10);

/** Records `device`'s treat for the day of `at`; one treat per device per day, newest days kept. */
export const recordTreat = (days: TreatDays, device: string, at: string): TreatDays => {
  const day = dayOf(at);
  const given = days[day] ?? [];
  if (given.includes(device)) return days;
  const next = { ...days, [day]: [...given, device] };
  const keep = Object.keys(next).sort().slice(-MAX_TREAT_DAYS);
  return Object.fromEntries(keep.map((d) => [d, next[d] ?? []]));
};
