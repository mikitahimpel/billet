import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { MediaKey, NoteId, UserId } from "@billet/contracts-domain/ids";
import { freeInk } from "@billet/contracts-domain/inks";
import { type Note, NoteText } from "@billet/contracts-domain/note";
import { RecordCatEventRequest } from "@billet/contracts-http-api/cat";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { ReactRequest } from "@billet/contracts-http-api/reaction";
import {
  type DemoBotAction,
  DemoBotState,
  demoBotMinGapMs,
  demoBotStep,
  nextWakeAt,
  noteSeen,
  seedOf,
  startDemoBot,
} from "../src/demo-bot.ts";
import { demoBotReplies } from "../src/demo-bot-replies.ts";

const user = Schema.decodeSync(UserId);
const noteId = Schema.decodeSync(NoteId);
const owner = user("user-owner");
const bot = user("user-bot");
const t0 = Date.parse("2099-10-31T12:00:00.000Z");
const second = 1000;
const minute = 60 * second;
const hour = 60 * minute;

const text = (id: string, author: UserId, at: number): Note => ({
  _tag: "Text",
  id: noteId(id),
  author,
  sentAt: at,
  text: Schema.decodeSync(NoteText)("hi"),
  ink: freeInk,
});
const photo = (id: string, author: UserId, at: number): Note => ({
  _tag: "Photo",
  id: noteId(id),
  author,
  sentAt: at,
  image: Schema.decodeSync(MediaKey)("pairs/p/notes/n.jpg"),
});

/** Steps the bot at every wake until `until`, as the room's alarm would. */
const run = (start: DemoBotState, until: number) => {
  let state = start;
  const actions: Array<{ at: number; action: DemoBotAction }> = [];
  for (let now = nextWakeAt(state); now <= until; now = nextWakeAt(state)) {
    const step = demoBotStep(state, now);
    if (step.action !== undefined) actions.push({ at: now, action: step.action });
    state = step.state;
  }
  return { state, actions };
};

describe("demo bot", () => {
  it("is seeded by its id, so the same bot plans the same", () => {
    expect(seedOf(bot)).toBe(seedOf(user("user-bot")));
    expect(seedOf(bot)).not.toBe(seedOf(owner));
    expect(startDemoBot(bot, owner, t0)).toEqual(startDemoBot(bot, owner, t0));
  });

  it("pets or feeds the cat a minute or few after it joins, then opens the gift", () => {
    const { actions } = run(startDemoBot(bot, owner, t0), t0 + 20 * minute);
    expect(actions.map(({ action }) => action._tag)).toEqual(["RecordCatEvent", "OpenGift"]);
    const [cat, gift] = actions;
    expect(cat!.at - t0).toBeGreaterThanOrEqual(1 * minute);
    expect(cat!.at - t0).toBeLessThanOrEqual(3 * minute);
    expect(gift!.at - t0).toBeGreaterThanOrEqual(5 * minute);
    expect(gift!.at - t0).toBeLessThanOrEqual(15 * minute);
    const request = cat!.action._tag === "RecordCatEvent" ? cat!.action.request : undefined;
    expect(Schema.is(RecordCatEventRequest)(request)).toBe(true);
  });

  it("answers an owner's text 5 to 30 seconds later with a canned line", () => {
    const quiet = run(startDemoBot(bot, owner, t0), t0 + hour).state;
    const at = t0 + hour;
    const waiting = noteSeen(quiet, text("n1", owner, at), at);
    expect(waiting.replyAt! - at).toBeGreaterThanOrEqual(5 * second);
    expect(waiting.replyAt! - at).toBeLessThanOrEqual(30 * second);

    const step = demoBotStep(waiting, nextWakeAt(waiting));
    expect(step.action?._tag).toBe("SendNote");
    const request = step.action?._tag === "SendNote" ? step.action.request : undefined;
    expect(Schema.is(SendNoteRequest)(request)).toBe(true);
    expect(request?._tag === "Text" && demoBotReplies.includes(request.text)).toBe(true);
    expect(step.state.replyAt).toBeUndefined();
  });

  it("gives a burst of owner notes one answer, and ignores its own notes", () => {
    const quiet = run(startDemoBot(bot, owner, t0), t0 + hour).state;
    let state = noteSeen(quiet, text("n1", owner, t0 + hour), t0 + hour);
    const replyAt = state.replyAt;
    for (let i = 2; i <= 5; i += 1) {
      state = noteSeen(state, text(`n${i}`, owner, t0 + hour + i * second), t0 + hour + i * second);
    }
    state = noteSeen(state, text("mine", bot, t0 + hour), t0 + hour);
    expect(state.replyAt).toBe(replyAt);
    const { actions } = run(state, t0 + hour + 10 * minute);
    expect(actions.filter(({ action }) => action._tag === "SendNote")).toHaveLength(1);
  });

  it("reacts to an owner's photo 10 to 60 seconds later", () => {
    const quiet = run(startDemoBot(bot, owner, t0), t0 + hour).state;
    const at = t0 + hour;
    const state = noteSeen(quiet, photo("p1", owner, at), at);
    const step = demoBotStep(state, nextWakeAt(state));
    expect(nextWakeAt(state) - at).toBeGreaterThanOrEqual(10 * second);
    expect(nextWakeAt(state) - at).toBeLessThanOrEqual(60 * second);
    const request = step.action?._tag === "React" ? step.action.request : undefined;
    expect(Schema.is(ReactRequest)(request)).toBe(true);
    expect(request?.note).toBe("p1");
    expect(step.state.reactions).toEqual([]);
    expect(noteSeen(quiet, photo("p2", bot, at), at)).toBe(quiet);
  });

  it("never acts twice within a minute, however much is due", () => {
    let state = run(startDemoBot(bot, owner, t0), t0 + hour).state;
    const at = t0 + hour;
    state = noteSeen(state, text("n1", owner, at), at);
    state = noteSeen(state, photo("p1", owner, at), at);
    state = noteSeen(state, photo("p2", owner, at), at);
    const { actions } = run(state, at + 10 * minute);
    expect(actions.map(({ action }) => action._tag)).toEqual(["SendNote", "React", "React"]);
    for (let i = 1; i < actions.length; i += 1) {
      expect(actions[i]!.at - actions[i - 1]!.at).toBeGreaterThanOrEqual(demoBotMinGapMs);
    }
    expect(demoBotStep(state, actions[0]!.at + demoBotMinGapMs - 1).action).toBeDefined();
    const after = demoBotStep(state, actions[0]!.at).state;
    expect(demoBotStep(after, actions[0]!.at + demoBotMinGapMs - 1).action).toBeUndefined();
  });

  it("keeps a gentle pace: the cat every few hours, the gift once a day", () => {
    const { actions } = run(startDemoBot(bot, owner, t0), t0 + 22 * hour);
    const cats = actions.filter(({ action }) => action._tag === "RecordCatEvent");
    const gifts = actions.filter(({ action }) => action._tag === "OpenGift");
    expect(cats.length).toBeGreaterThanOrEqual(4);
    expect(cats.length).toBeLessThanOrEqual(12);
    for (let i = 1; i < cats.length; i += 1) {
      expect(cats[i]!.at - cats[i - 1]!.at).toBeGreaterThanOrEqual(2 * hour);
    }
    expect(gifts).toHaveLength(1);
    const later = run(startDemoBot(bot, owner, t0), t0 + 40 * hour).actions;
    const opened = later.filter(({ action }) => action._tag === "OpenGift").map(({ at }) => at);
    expect(opened).toHaveLength(2);
    expect(opened[1]! - opened[0]!).toBeGreaterThanOrEqual(22 * hour);
    // Every cat event is a fresh id, so each is its own journal entry.
    const ids = cats.map(({ action }) =>
      action._tag === "RecordCatEvent" ? action.request.id : "",
    );
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("survives a round trip through storage", () => {
    const state = noteSeen(startDemoBot(bot, owner, t0), text("n1", owner, t0), t0);
    expect(Schema.decodeUnknownSync(DemoBotState)(structuredClone(state))).toEqual(state);
  });
});
