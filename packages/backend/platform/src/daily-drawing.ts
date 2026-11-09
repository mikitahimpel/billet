// Pure, so the room only stores and sends what these functions decide.

export type Season = "winter" | "spring" | "summer" | "autumn";

export interface DailyPrompt {
  readonly id: string;
  readonly text: string;
}

interface PromptEntry extends DailyPrompt {
  /** Without one the prompt fits any day. */
  readonly season?: Season;
}

/** Ids are stable: a client keeps them with its archive, so a reworded prompt keeps its id. */
export const PROMPTS: readonly PromptEntry[] = [
  { id: "where-you-are", text: "Draw where you are right now" },
  { id: "perfect-weekend", text: "Our perfect weekend" },
  { id: "how-i-see-you", text: "How I see you today" },
  { id: "made-you-smile", text: "Something that made you smile" },
  { id: "breakfast", text: "What you had for breakfast" },
  { id: "view-from-window", text: "The view from your window" },
  { id: "our-cat-dreams", text: "What the cat is dreaming about" },
  { id: "first-date", text: "Our first date, as you remember it" },
  { id: "your-mood", text: "Your mood as weather" },
  { id: "dream-house", text: "Our dream house" },
  { id: "pocket", text: "Something in your pocket or bag" },
  { id: "next-trip", text: "Where we should go next" },
  { id: "tiny-thing", text: "A tiny thing you love about me" },
  { id: "your-hands", text: "Your hand, traced or not" },
  { id: "soundtrack", text: "The song stuck in your head" },
  { id: "superpower", text: "Me with a superpower" },
  { id: "us-as-animals", text: "Us as two animals" },
  { id: "comfort-food", text: "Your comfort food" },
  { id: "desk", text: "Your desk or table, as it is" },
  { id: "lunch", text: "What lunch looked like" },
  { id: "inside-joke", text: "One of our inside jokes" },
  { id: "old-age", text: "Us at eighty" },
  { id: "sky-now", text: "The sky right now" },
  { id: "shoes", text: "The shoes you wore today" },
  { id: "plant", text: "A plant you passed today" },
  { id: "proud-of", text: "Something you're proud of this week" },
  { id: "worry", text: "A worry, small enough to draw" },
  { id: "hug", text: "What a hug feels like" },
  { id: "date-night", text: "Tonight's ideal date night" },
  { id: "our-song", text: "Our song, without words" },
  { id: "pet-idea", text: "A pet we should never get" },
  { id: "map-of-day", text: "A map of your day" },
  { id: "favourite-mug", text: "Your favourite mug" },
  { id: "kitchen", text: "Something in your kitchen" },
  { id: "self-portrait", text: "A self-portrait in ten seconds" },
  { id: "tomorrow", text: "What you're looking forward to tomorrow" },
  { id: "where-we-met", text: "Where we met" },
  { id: "if-i-were-there", text: "What we'd do if I were there" },
  { id: "cat-outfit", text: "The cat in an outfit" },
  { id: "invention", text: "An invention we need" },
  { id: "bed", text: "Your pillow, or whatever you'll sleep on" },
  { id: "snack", text: "The snack you want right now" },
  { id: "heard-today", text: "A sound you heard today" },
  { id: "monster", text: "A friendly monster under the bed" },
  { id: "word-of-day", text: "Today, in one word, then draw it" },
  { id: "fridge", text: "What's on your fridge door" },
  { id: "sleepy", text: "How sleepy you are, out of ten" },
  { id: "lucky-charm", text: "A lucky charm for me" },
  { id: "dance", text: "Your best dance move" },
  { id: "treasure", text: "Something you'd never throw away" },
  { id: "first-snow", text: "The first snow", season: "winter" },
  { id: "warm-drink", text: "Your warmest drink", season: "winter" },
  { id: "winter-coat", text: "Me in a giant winter coat", season: "winter" },
  { id: "snow-cat", text: "The cat meeting snow", season: "winter" },
  { id: "cosy-night", text: "A cosy night in", season: "winter" },
  { id: "new-year-wish", text: "A wish for the new year", season: "winter" },
  { id: "first-flower", text: "The first flower you saw", season: "spring" },
  { id: "rain-walk", text: "A walk in the rain", season: "spring" },
  { id: "picnic", text: "Our picnic basket", season: "spring" },
  { id: "spring-clean", text: "Something to throw out this spring", season: "spring" },
  { id: "birds", text: "A bird outside", season: "spring" },
  { id: "kite", text: "A kite for us", season: "spring" },
  { id: "ice-cream", text: "Your ice cream, scoops and all", season: "summer" },
  { id: "beach-day", text: "A beach day", season: "summer" },
  { id: "sunburn", text: "Where the sun found you", season: "summer" },
  { id: "summer-night", text: "A warm summer night", season: "summer" },
  { id: "road-trip", text: "Our road-trip car", season: "summer" },
  { id: "fruit", text: "The best fruit of the summer", season: "summer" },
  { id: "falling-leaf", text: "A falling leaf", season: "autumn" },
  { id: "jumper", text: "Your favourite jumper", season: "autumn" },
  { id: "pumpkin", text: "A pumpkin with your face", season: "autumn" },
  { id: "rainy-window", text: "Rain on the window", season: "autumn" },
  { id: "soup", text: "A soup for a cold day", season: "autumn" },
  { id: "costume", text: "A costume for the two of us", season: "autumn" },
];

const DAY = /^(\d{4})-(\d{2})-(\d{2})$/;
const DAY_MS = 86_400_000;

export const isDay = (value: unknown): value is string => {
  if (typeof value !== "string") return false;
  const match = DAY.exec(value);
  if (match === null) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
};

const dayNumber = (day: string): number => Math.floor(Date.parse(`${day}T00:00:00Z`) / DAY_MS);

export const addDays = (day: string, delta: number): string =>
  new Date(Date.parse(`${day}T00:00:00Z`) + delta * DAY_MS).toISOString().slice(0, 10);

/** Meteorological seasons of the northern hemisphere. */
export const seasonOf = (day: string): Season => {
  const month = Number(day.slice(5, 7));
  if (month === 12 || month <= 2) return "winter";
  if (month <= 5) return "spring";
  if (month <= 8) return "summer";
  return "autumn";
};

/** FNV-1a, 32 bits. */
const hash = (text: string): number => {
  let value = 0x811c9dc5;
  for (let index = 0; index < text.length; index += 1) {
    value ^= text.charCodeAt(index);
    value = Math.imul(value, 0x01000193);
  }
  return value >>> 0;
};

/** mulberry32, so a pair's order is the same on every call. */
const generator = (seed: number): (() => number) => {
  let state = seed;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296;
  };
};

const shuffled = <T>(items: readonly T[], seed: number): T[] => {
  const next = generator(seed);
  const out = [...items];
  for (let index = out.length - 1; index > 0; index -= 1) {
    const swap = Math.floor(next() * (index + 1));
    [out[index], out[swap]] = [out[swap] as T, out[index] as T];
  }
  return out;
};

/** Each pair walks its own shuffled order, so no prompt repeats until the season's set is used. */
export const promptFor = (pair: string, day: string): DailyPrompt => {
  const season = seasonOf(day);
  const pool = PROMPTS.filter((p) => p.season === undefined || p.season === season);
  const order = shuffled(pool, hash(`${pair}:${season}`));
  const chosen = order[dayNumber(day) % order.length] ?? PROMPTS[0]!;
  return { id: chosen.id, text: chosen.text };
};

/** UTC−12 to UTC+14 spans three dates. */
export const liveDays = (nowMs: number): readonly string[] => {
  const today = new Date(nowMs).toISOString().slice(0, 10);
  return [addDays(today, -1), today, addDays(today, 1)];
};

export interface DailyDrawing {
  readonly id: string;
  readonly ink: string;
  readonly at: string;
}

export type DailyDays = Readonly<Record<string, readonly string[]>>;

export const MAX_DAILY_DAYS = 60;
/** Well over a full canvas of strokes. */
export const MAX_DAILY_INK = 120_000;

/** The newest `MAX_DAILY_DAYS` days stay. */
export const recordDaily = (days: DailyDays, device: string, day: string): DailyDays => {
  const drew = days[day] ?? [];
  if (drew.includes(device)) return days;
  const next = { ...days, [day]: [...drew, device] };
  const keep = Object.keys(next).sort().slice(-MAX_DAILY_DAYS);
  return Object.fromEntries(keep.map((d) => [d, next[d] ?? []]));
};

export const droppedDays = (before: DailyDays, after: DailyDays): readonly string[] =>
  Object.keys(before).filter((day) => !(day in after));

/** The partner's drawing comes only once this device has drawn its own. */
export const dailyView = (
  pair: string,
  day: string,
  device: string,
  drawings: Readonly<Record<string, DailyDrawing>>,
): Readonly<Record<string, unknown>> => {
  const mine = drawings[device] ?? null;
  const theirsEntry = Object.entries(drawings).find(([who]) => who !== device);
  const theirs = theirsEntry?.[1] ?? null;
  return {
    type: "daily",
    day,
    prompt: promptFor(pair, day),
    mine,
    theirsDrawn: theirs !== null,
    theirs: mine === null ? null : theirs,
  };
};

export const promptsFrame = (pair: string, nowMs: number): Readonly<Record<string, unknown>> => ({
  type: "daily-prompts",
  prompts: Object.fromEntries(liveDays(nowMs).map((day) => [day, promptFor(pair, day)])),
});

/** Refuses a far-off `at`, so a day cannot be backdated. */
export const MAX_CLOCK_SKEW_MS = 36 * 3_600_000;

const OFFSET = /(Z|([+-])(\d{2}):(\d{2}))$/;

/** In minutes. */
export const offsetOf = (at: string): number | undefined => {
  const match = OFFSET.exec(at);
  if (match === null) return undefined;
  if (match[1] === "Z") return 0;
  const minutes = Number(match[3]) * 60 + Number(match[4]);
  return match[2] === "-" ? -minutes : minutes;
};

/** Local minutes after midnight. */
export const EVENING_START = 19 * 60;
/** No reminder is sent from here to `QUIET_END`. */
export const QUIET_START = 22 * 60;
export const QUIET_END = 8 * 60;

const localParts = (nowMs: number, offset: number) => {
  const local = new Date(nowMs + offset * 60_000);
  return {
    day: local.toISOString().slice(0, 10),
    minutes: local.getUTCHours() * 60 + local.getUTCMinutes(),
  };
};

export const isQuiet = (minutes: number): boolean => minutes >= QUIET_START || minutes < QUIET_END;

/** Device to the last local day it was reminded, so it is reminded at most once a day. */
export type Reminded = Readonly<Record<string, string>>;

export interface ReminderInputs {
  readonly devices: readonly string[];
  readonly offsets: Readonly<Record<string, number>>;
  readonly reminded: Reminded;
  readonly days: DailyDays;
}

export interface DueReminder {
  readonly device: string;
  readonly day: string;
  readonly partnerDrew: boolean;
}

const hasDrawn = (days: DailyDays, day: string, device: string): boolean =>
  (days[day] ?? []).includes(device);

/** A paired device that has not drawn its local day, in its evening, not reminded that day yet. */
export const dueReminders = (nowMs: number, inputs: ReminderInputs): readonly DueReminder[] => {
  const { devices, offsets, reminded, days } = inputs;
  if (devices.length < 2) return [];
  return devices.flatMap((device) => {
    const offset = offsets[device];
    if (offset === undefined) return [];
    const { day, minutes } = localParts(nowMs, offset);
    if (minutes < EVENING_START || isQuiet(minutes)) return [];
    if (reminded[device] === day || hasDrawn(days, day, device)) return [];
    const partner = devices.find((d) => d !== device);
    return [{ device, day, partnerDrew: partner !== undefined && hasDrawn(days, day, partner) }];
  });
};

/** The soonest evening start of a local day not drawn nor reminded on; undefined when none. */
export const nextReminderAt = (nowMs: number, inputs: ReminderInputs): number | undefined => {
  const { devices, offsets, reminded, days } = inputs;
  if (devices.length < 2) return undefined;
  const times = devices.flatMap((device) => {
    const offset = offsets[device];
    if (offset === undefined) return [];
    const { day } = localParts(nowMs, offset);
    for (const candidate of [day, addDays(day, 1)]) {
      if (reminded[device] === candidate || hasDrawn(days, candidate, device)) continue;
      const start = Date.parse(`${candidate}T00:00:00Z`) + EVENING_START * 60_000;
      const at = start - offset * 60_000;
      const end = at + (QUIET_START - EVENING_START) * 60_000;
      if (nowMs < end) return [Math.max(at, nowMs)];
    }
    return [];
  });
  return times.length === 0 ? undefined : Math.min(...times);
};

export const reminderText = (
  catName: string | undefined,
  prompt: DailyPrompt,
  partnerDrew: boolean,
): string => {
  const cat = catName ?? "The cat";
  return partnerDrew
    ? `${cat} is holding a drawing for you. Draw yours to see it 🎨`
    : `${cat} wonders what you'll draw today: ${prompt.text.toLowerCase()} ✏️`;
};
