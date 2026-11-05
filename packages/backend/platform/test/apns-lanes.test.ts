import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { NoteId, UserId, MediaKey } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { Note } from "@billet/contracts-domain/note";
import { PushPayload, pushPayloadKey } from "@billet/contracts-push/push-payload";
import type { ApnsPush, ApnsResult } from "../src/apns-client.ts";
import { enabledPushLanes, sendPushLane, type PushLaneDependencies } from "../src/apns-lanes.ts";
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
