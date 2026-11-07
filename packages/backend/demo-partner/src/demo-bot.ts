import { Schema } from "effect";
import type { CatEvent } from "@billet/contracts-domain/cat";
import { EpochMillis, IdempotencyKey, NoteId, UserId } from "@billet/contracts-domain/ids";
import { freeInk } from "@billet/contracts-domain/inks";
import type { Note } from "@billet/contracts-domain/note";
import type { Reaction } from "@billet/contracts-domain/reaction";
import type { RecordCatEventRequest } from "@billet/contracts-http-api/cat";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import type { ReactRequest } from "@billet/contracts-http-api/reaction";
import { demoBotReplies } from "./demo-bot-replies.ts";

const second = 1000;
const minute = 60 * second;
const hour = 60 * minute;

/** The bot never acts twice within this many milliseconds, however much is due. */
export const demoBotMinGapMs = minute;
/** Photos waiting for a reaction; more in the meantime go unanswered. */
const maxPendingReactions = 3;

const decodeKey = Schema.decodeSync(IdempotencyKey);

/**
 * What a demo bot has in mind. Every time is epoch milliseconds by the room's clock. `draws`
 * counts the random numbers taken from `seed`, so the same history always plans the same.
 */
export const DemoBotState = Schema.Struct({
  bot: UserId,
  owner: UserId,
  seed: Schema.Int,
  draws: Schema.Int,
  lastActionAt: Schema.optional(EpochMillis),
  /** When the bot answers the owner's last unanswered text note. */
  replyAt: Schema.optional(EpochMillis),
  /** Owner photos the bot will react to, oldest first. */
  reactions: Schema.Array(Schema.Struct({ note: NoteId, at: EpochMillis })),
  catAt: EpochMillis,
  giftAt: EpochMillis,
  /** When the bot plays its part of today's Who knows who round, after the owner played theirs. */
  guessAt: Schema.optional(EpochMillis),
});
export type DemoBotState = typeof DemoBotState.Type;

/** What the bot does, as the request a phone would send for it. */
export type DemoBotAction =
  | { readonly _tag: "SendNote"; readonly request: SendNoteRequest }
  | { readonly _tag: "React"; readonly request: ReactRequest }
  | { readonly _tag: "RecordCatEvent"; readonly request: RecordCatEventRequest }
  | { readonly _tag: "OpenGift" }
  /** Answers every question of today's round the bot has not answered, the `n`th with `options[n]`. */
  | { readonly _tag: "PlayGuess"; readonly options: ReadonlyArray<number> };

/** A 32-bit seed from the bot's id (FNV-1a), so a bot keeps its habits across restarts. */
export const seedOf = (bot: string): number => {
  let hash = 0x811c9dc5;
  for (let i = 0; i < bot.length; i += 1) {
    hash ^= bot.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
};

/** The `n`th 32-bit number of `seed`'s stream (a SplitMix32 step), independent of the others. */
const randomAt = (seed: number, n: number): number => {
  let z = (seed + Math.imul(n + 1, 0x9e3779b9)) >>> 0;
  z = Math.imul(z ^ (z >>> 16), 0x85ebca6b);
  z = Math.imul(z ^ (z >>> 13), 0xc2b2ae35);
  return (z ^ (z >>> 16)) >>> 0;
};

/** Takes numbers off a seed's stream from `draws` on; `drawn` is the count after them. */
const drawer = (seed: number, draws: number) => {
  let next = draws;
  const word = () => randomAt(seed, next++);
  const unit = () => word() / 0x1_0000_0000;
  const between = (low: number, high: number) => Math.floor(low + unit() * (high - low + 1));
  return {
    unit,
    between,
    pick: <A>(choices: readonly [A, ...ReadonlyArray<A>]): A =>
      choices[between(0, choices.length - 1)] ?? choices[0],
    key: () => {
      const hex = [word(), word(), word(), word()]
        .map((n) => n.toString(16).padStart(8, "0"))
        .join("");
      const groups = [
        [0, 8],
        [8, 12],
        [12, 16],
        [16, 20],
        [20, 32],
      ] as const;
      return decodeKey(groups.map(([from, to]) => hex.slice(from, to)).join("-"));
    },
    drawn: () => next,
  };
};
type Drawer = ReturnType<typeof drawer>;

/** The bot as it joins: it looks in on the cat a minute or two in, and opens a gift soon after. */
export const startDemoBot = (bot: UserId, owner: UserId, now: number): DemoBotState => {
  const seed = seedOf(bot);
  const draw = drawer(seed, 0);
  const catAt = now + draw.between(1 * minute, 3 * minute);
  const giftAt = now + draw.between(5 * minute, 15 * minute);
  return { bot, owner, seed, draws: draw.drawn(), reactions: [], catAt, giftAt };
};

/**
 * What a note just stored makes the bot plan: an answer 5 to 30 seconds after an owner's text, a
 * reaction 10 to 60 seconds after an owner's photo. A text while an answer is pending changes
 * nothing, so a burst gets one answer.
 */
export const noteSeen = (state: DemoBotState, note: Note, now: number): DemoBotState => {
  if (note.author !== state.owner) return state;
  const draw = drawer(state.seed, state.draws);
  switch (note._tag) {
    case "Text": {
      if (state.replyAt !== undefined) return state;
      const replyAt = now + draw.between(5 * second, 30 * second);
      return { ...state, replyAt, draws: draw.drawn() };
    }
    case "Photo": {
      if (state.reactions.length >= maxPendingReactions) return state;
      const at = now + draw.between(10 * second, 60 * second);
      return {
        ...state,
        reactions: [...state.reactions, { note: note.id, at }],
        draws: draw.drawn(),
      };
    }
    case "Drawing":
      return state;
  }
};

/**
 * What an owner's Who knows who answer makes the bot plan: its own part 10 to 40 seconds later.
 * More answers while that is pending change nothing.
 */
export const guessSeen = (state: DemoBotState, by: UserId, now: number): DemoBotState => {
  if (by !== state.owner || state.guessAt !== undefined) return state;
  const draw = drawer(state.seed, state.draws);
  return { ...state, guessAt: now + draw.between(10 * second, 40 * second), draws: draw.drawn() };
};

/** Every few hours: mostly a pet, sometimes a small meal. */
const catEvent = (draw: Drawer): CatEvent =>
  draw.unit() < 0.3 ? { _tag: "Fed", grams: draw.between(20, 60) } : { _tag: "Petted" };

const reactionOf = (draw: Drawer): Reaction =>
  draw.pick<Reaction>(["heart", "heart", "heart", "laugh", "wow", "fire"]);

type Plan = "reply" | "react" | "cat" | "gift" | "guess";

const planned = (state: DemoBotState): ReadonlyArray<readonly [Plan, number]> => {
  const [photo] = state.reactions;
  return [
    ...(state.replyAt === undefined ? [] : [["reply", state.replyAt] as const]),
    ...(photo === undefined ? [] : [["react", photo.at] as const]),
    ...(state.guessAt === undefined ? [] : [["guess", state.guessAt] as const]),
    ["cat", state.catAt],
    ["gift", state.giftAt],
  ];
};

/** When the bot next has something to do: never sooner than a minute after its last action. */
export const nextWakeAt = (state: DemoBotState): number => {
  const earliest = Math.min(...planned(state).map(([, at]) => at));
  return state.lastActionAt === undefined
    ? earliest
    : Math.max(earliest, state.lastActionAt + demoBotMinGapMs);
};

/**
 * The one action due at `now`, the earliest planned first, and the state after it; nothing within
 * a minute of the last action. The action leaves the plan whether or not the room accepts it, so
 * a refused one (no cat yet, the day's gift already opened) is not retried in a loop.
 */
export const demoBotStep = (
  state: DemoBotState,
  now: number,
): { readonly action: DemoBotAction | undefined; readonly state: DemoBotState } => {
  const resting = state.lastActionAt !== undefined && now < state.lastActionAt + demoBotMinGapMs;
  const due = planned(state)
    .filter(([, at]) => at <= now)
    .toSorted(([, a], [, b]) => a - b)[0];
  if (resting || due === undefined) return { action: undefined, state };

  const draw = drawer(state.seed, state.draws);
  const acted = (change: Partial<DemoBotState>): DemoBotState => ({
    ...state,
    ...change,
    lastActionAt: now,
    draws: draw.drawn(),
  });
  switch (due[0]) {
    case "reply": {
      const request: SendNoteRequest = {
        _tag: "Text",
        key: draw.key(),
        text: draw.pick(demoBotReplies),
        ink: freeInk,
      };
      return { action: { _tag: "SendNote", request }, state: acted({ replyAt: undefined }) };
    }
    case "react": {
      const [photo, ...others] = state.reactions;
      if (photo === undefined) return { action: undefined, state };
      const request: ReactRequest = { note: photo.note, reaction: reactionOf(draw) };
      return { action: { _tag: "React", request }, state: acted({ reactions: others }) };
    }
    case "cat": {
      const request: RecordCatEventRequest = { id: draw.key(), event: catEvent(draw) };
      const catAt = now + draw.between(2 * hour, 5 * hour);
      return { action: { _tag: "RecordCatEvent", request }, state: acted({ catAt }) };
    }
    case "gift": {
      const giftAt = now + draw.between(22 * hour, 26 * hour);
      return { action: { _tag: "OpenGift" }, state: acted({ giftAt }) };
    }
    case "guess": {
      const options = Array.from({ length: 5 }, () => draw.between(0, 3));
      return { action: { _tag: "PlayGuess", options }, state: acted({ guessAt: undefined }) };
    }
  }
};
