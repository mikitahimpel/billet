import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { NoteId, UserId, MediaKey } from "@billet/contracts-domain/ids";
import { LocalDay } from "@billet/contracts-domain/coins";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import type { LoveStreak } from "@billet/contracts-domain/streak";
import { Note } from "@billet/contracts-domain/note";
import { PushPayload, pushPayloadKey } from "@billet/contracts-push/push-payload";
import type { ApnsPush, ApnsResult } from "../src/apns-client.ts";
import {
  enabledPushLanes,
  guessDeliveryId,
  matchDeliveryId,
  reactionDeliveryId,
  riddleDeliveryId,
  riddleEndDeliveryId,
  sendPushLane,
  streakLitDeliveryId,
  streakTurnDeliveryId,
  type PushLaneDependencies,
} from "../src/apns-lanes.ts";
import {
  alertBody,
  byteLength,
  liveActivityBody,
  maxPushBytes,
  ordinal,
  widgetBody,
} from "../src/apns-payloads.ts";

const alice = Schema.decodeUnknownSync(UserId)("user-alice");
const bob = Schema.decodeUnknownSync(UserId)("user-bob");
const id = Schema.decodeUnknownSync(NoteId)("note-1");
const image = Schema.decodeUnknownSync(MediaKey)("pairs/pair-1/notes/note-1.png");
const compact = CompactStrokes.make({
  version: 1,
  strokes: [{ color: "#7B4FE0", width: 33, points: [10, 20, 500, 900] }],
});
const drawing = Note.cases.Drawing.make({
  id,
  author: alice,
  sentAt: 1,
  compact,
  image,
  paper: "sky",
});
const photo = Note.cases.Photo.make({ id, author: alice, sentAt: 1, image });

/** A compact rendition as large as the encoder's 3 KB budget allows. */
const fullCompact = (() => {
  const points: number[] = [];
  let strokes = CompactStrokes.make({ version: 1, strokes: [] });
  while (byteLength(strokes) < 3072 - 10) {
    points.push(1023, 2047);
    strokes = CompactStrokes.make({
      version: 1,
      strokes: [{ color: "#7B4FE0", width: 33, points: [...points] }],
    });
  }
  return strokes;
})();

const deps = (overrides: Partial<PushLaneDependencies> = {}) => {
  const sent: ApnsPush[] = [];
  const dropped: string[] = [];
  const results: ApnsResult[] = [];
  const dependencies: PushLaneDependencies = {
    note: async () => drawing,
    reaction: async (rev) => ({
      reaction: { rev, note: id, by: bob, at: 2, reaction: "heart" },
      note: photo,
    }),
    match: async () => ({ recipient: alice, name: "Arrival" }),
    guess: async () => ({ recipient: bob, role: "subject", count: 5 }),
    riddle: async () => ({
      drawer: alice,
      guesser: bob,
      word: "north pole",
      tries: 0,
      state: "Open",
    }),
    streak: async () => undefined,
    recipient: async (note) => (note.author === alice ? bob : alice),
    tokens: async () => [
      { token: "aa", environment: "production" },
      { token: "bb", environment: "sandbox" },
    ],
    dropToken: async (token) => {
      dropped.push(token);
    },
    send: async (push) => {
      sent.push(push);
      return results.shift() ?? { _tag: "Delivered" };
    },
    nowSeconds: () => 1_700_000_000,
    ...overrides,
  };
  return { dependencies, sent, dropped, results };
};

describe("which push lanes a room uses", () => {
  it("none without an APNs key, widget and alert with one, Live Activity only when switched on", () => {
    expect(enabledPushLanes({})).toEqual([]);
    expect(enabledPushLanes({ APNS_KEY: "k" })).toEqual([]);
    expect(enabledPushLanes({ APNS_KEY: "k", APNS_KEY_ID: "id" })).toEqual([
      "WidgetPush",
      "AlertPush",
    ]);
    expect(
      enabledPushLanes({ APNS_KEY: "k", APNS_KEY_ID: "id", LIVE_ACTIVITY_PUSH: "true" }),
    ).toEqual(["WidgetPush", "AlertPush"]);
    expect(
      enabledPushLanes({ APNS_KEY: "k", APNS_KEY_ID: "id", LIVE_ACTIVITY_PUSH: "on" }),
    ).toEqual(["WidgetPush", "AlertPush", "LiveActivityPush"]);
  });
});

describe("one try of a push lane", () => {
  it("sends the note to each of the partner's devices, as the lane's push type", async () => {
    const tokens: Array<[string, string]> = [];
    const { dependencies, sent } = deps({
      tokens: async (user, kind) => {
        tokens.push([user, kind]);
        return [{ token: "aa", environment: "production" }];
      },
    });
    expect(await sendPushLane({ noteId: id, lane: "WidgetPush" }, dependencies)).toBe("Delivered");
    expect(tokens).toEqual([[bob, "widget"]]);
    expect(sent.map((push) => [push.pushType, push.token, push.collapseId])).toEqual([
      ["widgets", "aa", id],
    ]);
  });

  it("drops a dead token, and is delivered when another device took the push", async () => {
    const { dependencies, dropped, results } = deps();
    results.push({ _tag: "Unregistered", reason: "Unregistered" }, { _tag: "Delivered" });
    expect(await sendPushLane({ noteId: id, lane: "AlertPush" }, dependencies)).toBe("Delivered");
    expect(dropped).toEqual(["aa"]);
  });

  it("still reports a delivery when dropping a dead token fails", async () => {
    const { dependencies, results } = deps({
      dropToken: async () => {
        throw new Error("D1 down");
      },
    });
    results.push({ _tag: "Unregistered", reason: "Unregistered" }, { _tag: "Delivered" });
    expect(await sendPushLane({ noteId: id, lane: "AlertPush" }, dependencies)).toBe("Delivered");
  });

  it("retries while a failure may pass, and gives up when none will", async () => {
    const retry = deps();
    retry.results.push({ _tag: "Retry", reason: "429" }, { _tag: "Rejected", reason: "BadTopic" });
    expect(await sendPushLane({ noteId: id, lane: "AlertPush" }, retry.dependencies)).toBe("Retry");

    const rejected = deps();
    rejected.results.push({ _tag: "Rejected", reason: "x" }, { _tag: "Unregistered", reason: "y" });
    expect(await sendPushLane({ noteId: id, lane: "AlertPush" }, rejected.dependencies)).toBe(
      "Abandon",
    );
  });

  it("gives up with no one to send to: no tokens, no recipient, no note, or a lane it does not know", async () => {
    expect(
      await sendPushLane(
        { noteId: id, lane: "AlertPush" },
        deps({ tokens: async () => [] }).dependencies,
      ),
    ).toBe("Abandon");
    expect(
      await sendPushLane(
        { noteId: id, lane: "AlertPush" },
        deps({ recipient: async () => undefined }).dependencies,
      ),
    ).toBe("Abandon");
    expect(
      await sendPushLane(
        { noteId: id, lane: "AlertPush" },
        deps({ note: async () => undefined }).dependencies,
      ),
    ).toBe("Abandon");
    expect(await sendPushLane({ noteId: id, lane: "WebSocket" }, deps().dependencies)).toBe(
      "Abandon",
    );
  });

  it("has nothing to send on the Live Activity lane for a photo", async () => {
    const { dependencies, sent } = deps({ note: async () => photo });
    expect(await sendPushLane({ noteId: id, lane: "LiveActivityPush" }, dependencies)).toBe(
      "Delivered",
    );
    expect(sent).toEqual([]);
  });
});

describe("one try of a reaction's push", () => {
  const delivery = reactionDeliveryId(3);

  it("alerts the photo's author, collapsing earlier reactions to the same photo", async () => {
    const users: string[] = [];
    const { dependencies, sent } = deps({
      tokens: async (user) => {
        users.push(user);
        return [{ token: "aa", environment: "production" }];
      },
    });
    expect(await sendPushLane({ noteId: delivery, lane: "AlertPush" }, dependencies)).toBe(
      "Delivered",
    );
    expect(users).toEqual([alice]);
    expect(sent.map((push) => [push.pushType, push.collapseId])).toEqual([["alert", `r-${id}`]]);
    expect(
      Schema.decodeUnknownSync(PushPayload)(
        (sent[0]!.body as Record<string, unknown>)[pushPayloadKey],
      ),
    ).toEqual(PushPayload.cases.Reaction.make({ noteId: id, by: bob, reaction: "heart" }));
  });

  it("sends nothing on the other lanes, nor for a reaction taken back", async () => {
    const widget = deps();
    expect(await sendPushLane({ noteId: delivery, lane: "WidgetPush" }, widget.dependencies)).toBe(
      "Delivered",
    );
    const takenBack = deps({
      reaction: async (rev) => ({ reaction: { rev, note: id, by: bob, at: 2 }, note: photo }),
    });
    expect(
      await sendPushLane({ noteId: delivery, lane: "AlertPush" }, takenBack.dependencies),
    ).toBe("Delivered");
    expect([...widget.sent, ...takenBack.sent]).toEqual([]);
  });

  it("gives up on a reaction changed since", async () => {
    const { dependencies, sent } = deps({ reaction: async () => undefined });
    expect(await sendPushLane({ noteId: delivery, lane: "AlertPush" }, dependencies)).toBe(
      "Abandon",
    );
    expect(sent).toEqual([]);
  });
});

describe("a Pick tonight match", () => {
  const delivery = matchDeliveryId("movie:329865", 1_700_000_000_000);

  it("is an alert to the partner who swiped first, naming the title", async () => {
    const asked: Array<[string, number]> = [];
    const { dependencies, sent } = deps({
      match: async (key, at) => {
        asked.push([key, at]);
        return { recipient: alice, name: "Arrival" };
      },
    });
    expect(await sendPushLane({ noteId: delivery, lane: "AlertPush" }, dependencies)).toBe(
      "Delivered",
    );
    expect(asked).toEqual([["movie:329865", 1_700_000_000_000]]);
    expect(sent.map((push) => [push.pushType, push.collapseId])).toEqual([
      ["alert", "m-movie:329865"],
      ["alert", "m-movie:329865"],
    ]);
    expect((sent[0]!.body as { aps: unknown }).aps).toMatchObject({
      alert: { title: "It's a match!", body: "You both want to watch Arrival" },
    });
  });

  it("sends nothing on the other lanes, and gives up on a match taken back", async () => {
    const widget = deps();
    expect(await sendPushLane({ noteId: delivery, lane: "WidgetPush" }, widget.dependencies)).toBe(
      "Delivered",
    );
    const gone = deps({ match: async () => undefined });
    expect(await sendPushLane({ noteId: delivery, lane: "AlertPush" }, gone.dependencies)).toBe(
      "Abandon",
    );
    expect([...widget.sent, ...gone.sent]).toEqual([]);
  });
});

describe("a finished Who knows who part", () => {
  const delivery = guessDeliveryId("2026-11-05", alice);

  it("is an alert to the partner in its own thread, worded for the part played", async () => {
    const asked: Array<[string, string]> = [];
    const subject = deps({
      guess: async (day, member) => {
        asked.push([day, member]);
        return { recipient: bob, role: "subject", count: 5 };
      },
    });
    expect(await sendPushLane({ noteId: delivery, lane: "AlertPush" }, subject.dependencies)).toBe(
      "Delivered",
    );
    expect(asked).toEqual([["2026-11-05", alice]]);
    expect(subject.sent.map((push) => [push.pushType, push.collapseId])).toEqual([
      ["alert", "g-2026-11-05"],
      ["alert", "g-2026-11-05"],
    ]);
    expect((subject.sent[0]!.body as { aps: unknown }).aps).toEqual({
      alert: {
        title: "Who knows who",
        body: "Your partner answered 5 questions about themselves. Your turn to guess",
      },
      sound: "default",
      "thread-id": "who-knows-who",
    });

    const guesser = deps({ guess: async () => ({ recipient: bob, role: "guesser", count: 5 }) });
    await sendPushLane({ noteId: delivery, lane: "AlertPush" }, guesser.dependencies);
    expect((guesser.sent[0]!.body as { aps: { alert: unknown } }).aps.alert).toEqual({
      title: "Who knows who",
      body: "Your partner guessed 5 things about you. Answer to see how they did",
    });
  });

  it("sends nothing on the other lanes, and gives up once the round revealed or closed", async () => {
    const widget = deps();
    expect(await sendPushLane({ noteId: delivery, lane: "WidgetPush" }, widget.dependencies)).toBe(
      "Delivered",
    );
    const gone = deps({ guess: async () => undefined });
    expect(await sendPushLane({ noteId: delivery, lane: "AlertPush" }, gone.dependencies)).toBe(
      "Abandon",
    );
    expect([...widget.sent, ...gone.sent]).toEqual([]);
  });
});

describe("the love streak", () => {
  const today = Schema.decodeUnknownSync(LocalDay)("2026-11-05");
  const yesterday = Schema.decodeUnknownSync(LocalDay)("2026-11-04");
  const waiting: LoveStreak = {
    days: 4,
    best: 9,
    lastDay: yesterday,
    marks: [{ user: alice, day: today }],
  };
  const lit: LoveStreak = { days: 5, best: 9, lastDay: today };
  const room = (streak: LoveStreak) => async () => ({ streak, members: [alice, bob] });
  const decode = Schema.decodeUnknownSync(PushPayload);
  const turn = { noteId: streakTurnDeliveryId(today, alice), lane: "AlertPush" } as const;
  const litDay = { noteId: streakLitDeliveryId(today, bob), lane: "AlertPush" } as const;

  it("tells the partner it's their turn, with the streak for the widgets", async () => {
    const tokens: string[] = [];
    const { dependencies, sent } = deps({
      streak: room(waiting),
      tokens: async (user) => {
        tokens.push(user);
        return [{ token: "aa", environment: "production" }];
      },
    });
    expect(await sendPushLane(turn, dependencies)).toBe("Delivered");
    expect(tokens).toEqual([bob]);
    const body = sent[0]!.body as Record<string, unknown>;
    expect(decode(body[pushPayloadKey])).toEqual(
      PushPayload.cases.Streak.make({ you: bob, lit: false, streak: waiting }),
    );
    expect(sent[0]!.collapseId).toBe("s-2026-11-05");
  });

  it("tells the partner who went first that the day lit", async () => {
    const tokens: string[] = [];
    const { dependencies, sent } = deps({
      streak: room(lit),
      tokens: async (user) => {
        tokens.push(user);
        return [{ token: "aa", environment: "production" }];
      },
    });
    expect(await sendPushLane(litDay, dependencies)).toBe("Delivered");
    expect(tokens).toEqual([alice]);
    expect((sent[0]!.body as { aps: { alert: unknown } }).aps.alert).toEqual({
      title: "Ourio",
      body: "Today's flame is lit: 5 days in a row 🔥",
    });
  });

  it("drops a turn once the day lit or the partner did their part, and other lanes", async () => {
    const answered: LoveStreak = {
      ...waiting,
      marks: [
        { user: alice, day: today },
        { user: bob, day: today },
      ],
    };
    for (const streak of [lit, answered]) {
      const { dependencies, sent } = deps({ streak: room(streak) });
      expect(await sendPushLane(turn, dependencies)).toBe("Abandon");
      expect(sent).toEqual([]);
    }
    const later = deps({
      streak: room({ ...lit, lastDay: Schema.decodeUnknownSync(LocalDay)("2026-11-06") }),
    });
    expect(await sendPushLane(litDay, later.dependencies)).toBe("Abandon");
    const widget = deps({ streak: room(waiting) });
    expect(await sendPushLane({ ...turn, lane: "WidgetPush" }, widget.dependencies)).toBe(
      "Delivered",
    );
    expect(widget.sent).toEqual([]);
  });
});

describe("a draw-guess riddle", () => {
  const id = "00000000-0000-4000-8000-000000000001";
  const alertOf = (push: ApnsPush | undefined) => (push!.body as { aps: unknown }).aps;

  it("is an alert to the guesser while it is open, with how many letters", async () => {
    const sent = deps();
    const entry = { noteId: riddleDeliveryId(id), lane: "AlertPush" } as const;
    expect(await sendPushLane(entry, sent.dependencies)).toBe("Delivered");
    expect(sent.sent.map((push) => push.collapseId)).toEqual([`d-${id}`, `d-${id}`]);
    expect(alertOf(sent.sent[0])).toEqual({
      alert: { title: "Ourio", body: "Your partner drew you a riddle. 9 letters." },
      sound: "default",
      "thread-id": "draw-guess",
    });
    const asked: Array<string> = [];
    const tokens = deps({
      tokens: async (user) => {
        asked.push(user);
        return [];
      },
    });
    await sendPushLane(entry, tokens.dependencies);
    expect(asked).toEqual([bob]);
  });

  it("tells the drawer how the round ended, and nothing on the other lanes", async () => {
    const solved = deps({
      riddle: async () => ({ drawer: alice, guesser: bob, word: "cat", tries: 2, state: "Solved" }),
    });
    const ended = { noteId: riddleEndDeliveryId(id), lane: "AlertPush" } as const;
    expect(await sendPushLane(ended, solved.dependencies)).toBe("Delivered");
    expect((alertOf(solved.sent[0]) as { alert: unknown }).alert).toEqual({
      title: "Ourio",
      body: "Your partner guessed “cat” on the 2nd try 🎉",
    });
    const gaveUp = deps({
      riddle: async () => ({
        drawer: alice,
        guesser: bob,
        word: "cat",
        tries: 4,
        state: "GivenUp",
      }),
    });
    await sendPushLane(ended, gaveUp.dependencies);
    expect((alertOf(gaveUp.sent[0]) as { alert: unknown }).alert).toEqual({
      title: "Ourio",
      body: "Your partner gave up on “cat”",
    });
    const widget = deps();
    expect(
      await sendPushLane({ noteId: riddleDeliveryId(id), lane: "WidgetPush" }, widget.dependencies),
    ).toBe("Delivered");
    expect(widget.sent).toEqual([]);
  });

  it("gives up on a riddle no longer held, a new one already ended, or an end still open", async () => {
    const gone = deps({ riddle: async () => undefined });
    expect(
      await sendPushLane({ noteId: riddleDeliveryId(id), lane: "AlertPush" }, gone.dependencies),
    ).toBe("Abandon");
    const open = deps();
    expect(
      await sendPushLane({ noteId: riddleEndDeliveryId(id), lane: "AlertPush" }, open.dependencies),
    ).toBe("Abandon");
    const solved = deps({
      riddle: async () => ({ drawer: alice, guesser: bob, word: "cat", tries: 1, state: "Solved" }),
    });
    expect(
      await sendPushLane({ noteId: riddleDeliveryId(id), lane: "AlertPush" }, solved.dependencies),
    ).toBe("Abandon");
    expect([...gone.sent, ...open.sent, ...solved.sent]).toEqual([]);
  });

  it("counts tries in words", () => {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 101].map(ordinal)).toEqual([
      "1st",
      "2nd",
      "3rd",
      "4th",
      "11th",
      "12th",
      "13th",
      "21st",
      "22nd",
      "101st",
    ]);
  });
});

describe("push bodies", () => {
  const decode = Schema.decodeUnknownSync(PushPayload);

  it("puts the drawing beside aps, for the notification extension", () => {
    const body = alertBody(drawing) as Record<string, unknown>;
    expect(body.aps).toMatchObject({ "mutable-content": 1 });
    expect(decode(body[pushPayloadKey])).toEqual(
      PushPayload.cases.Alert.make({ noteId: id, author: alice, compact, paper: "sky" }),
    );
    expect((widgetBody(drawing) as { aps: unknown }).aps).toEqual({ "content-changed": true });
  });

  it("starts the Live Activity with the strokes as its content state", () => {
    const body = liveActivityBody(drawing, 1_700_000_000) as { aps: Record<string, unknown> };
    expect(body.aps).toMatchObject({
      event: "start",
      timestamp: 1_700_000_000,
      "attributes-type": "DrawingAttributes",
    });
    expect(decode(body.aps["content-state"])).toEqual(
      PushPayload.cases.LiveActivity.make({ noteId: id, author: alice, compact, paper: "sky" }),
    );
    expect(liveActivityBody(photo, 1)).toBeUndefined();
  });

  it("stays under 4 KB on every lane with the largest drawing the encoder makes", () => {
    const largest = Note.cases.Drawing.make({
      id,
      author: alice,
      sentAt: 1,
      compact: fullCompact,
      image,
      paper: "cream",
    });
    expect(byteLength(fullCompact)).toBeGreaterThan(3000);
    for (const body of [
      alertBody(largest),
      widgetBody(largest),
      liveActivityBody(largest, 1_700_000_000),
    ]) {
      expect(byteLength(body)).toBeLessThan(maxPushBytes);
    }
  });
});
