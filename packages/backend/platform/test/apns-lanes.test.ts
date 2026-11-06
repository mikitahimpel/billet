import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { NoteId, UserId, MediaKey } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { Note } from "@billet/contracts-domain/note";
import { PushPayload, pushPayloadKey } from "@billet/contracts-push/push-payload";
import type { ApnsPush, ApnsResult } from "../src/apns-client.ts";
import {
  enabledPushLanes,
  guessDeliveryId,
  matchDeliveryId,
  reactionDeliveryId,
  sendPushLane,
  type PushLaneDependencies,
} from "../src/apns-lanes.ts";
import {
  alertBody,
  byteLength,
  liveActivityBody,
  maxPushBytes,
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
