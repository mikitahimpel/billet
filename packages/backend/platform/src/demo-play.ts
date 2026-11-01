// Play frames for the demo room: petting the cat and giving the day's treat.

export const MAX_QUEUED_PETS = 10;
export const MAX_TREAT_DAYS = 90;

export type PlayKind = "pet" | "treat";

export interface PlayFrame {
  readonly id: string;
  readonly kind: PlayKind;
  readonly at: string;
}

/** Calendar day (`YYYY-MM-DD`) mapped to the devices that gave a treat that day. */
export type TreatDays = Readonly<Record<string, readonly string[]>>;

export interface QueuedPet extends PlayFrame {
  readonly from: string;
  readonly to: string;
}

const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const ISO_TIME = /^(\d{4}-\d{2}-\d{2})T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})$/;

/** Reads a `play` frame, or returns undefined when any field is missing or malformed. */
export const parsePlay = (frame: Readonly<Record<string, unknown>>): PlayFrame | undefined => {
  const { id, kind, at } = frame;
  if (typeof id !== "string" || !UUID.test(id)) return undefined;
  if (kind !== "pet" && kind !== "treat") return undefined;
  if (typeof at !== "string" || !ISO_TIME.test(at) || Number.isNaN(Date.parse(at))) {
    return undefined;
  }
  return { id, kind, at };
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
