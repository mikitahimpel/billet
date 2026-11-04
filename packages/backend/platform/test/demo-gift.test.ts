import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { MAX_GIFT_MESSAGE, parsePlay } from "../src/demo-play.ts";
import type { DemoRoom } from "../src/demo-room-durable-object.ts";
import { routeDemo } from "../src/demo-route.ts";
import { waitFor } from "./demo-wait.ts";

type Rooms = DurableObjectNamespace<DemoRoom>;
const { DEMO_ROOM } = env as unknown as { DEMO_ROOM: Rooms };

const alice = "11111111-1111-4111-8111-111111111111";
const bob = "22222222-2222-4222-8222-222222222222";
const uuid = (n: number) => `eeeeeeee-eeee-4eee-8eee-${String(n).padStart(12, "0")}`;
const at = "2026-11-04T19:30:00+01:00";

type Frame = Record<string, unknown>;

interface Peer {
  readonly socket: WebSocket;
  readonly frames: Frame[];
  readonly waitFor: (check: (frames: Frame[]) => boolean, what: string) => Promise<void>;
  readonly sendAcked: (frame: Frame) => Promise<void>;
}

const connect = async (code: string, device: string): Promise<Peer> => {
  const response = await routeDemo(
    new Request(`https://host/demo/rooms/${code}/socket?device=${device}`, {
      headers: { Upgrade: "websocket" },
    }),
    DEMO_ROOM,
  )!;
  const socket = response.webSocket!;
  const frames: Frame[] = [];
  socket.accept();
  socket.addEventListener("message", (event) => {
    frames.push(JSON.parse(event.data as string));
  });
  const peer: Peer = {
    socket,
    frames,
    waitFor: (check, what) => waitFor(() => check(frames), what),
    sendAcked: async (frame) => {
      socket.send(JSON.stringify(frame));
      await waitFor(
        () => frames.some((f) => f["type"] === "ack" && f["id"] === frame["id"]),
        `ack of ${String(frame["id"])}`,
      );
    },
  };
  await peer.waitFor((f) => f.some((x) => x["type"] === "room"), "the room frame");
  return peer;
};

const gifts = (frames: Frame[]) => frames.filter((f) => f["type"] === "gift");

describe("gift frames", () => {
  it("reads a gift with and without a note", () => {
    expect(parsePlay({ id: uuid(1), kind: "gift", at, item: "furniture-mouse" })).toEqual({
      id: uuid(1),
      kind: "gift",
      at,
      item: "furniture-mouse",
    });
    expect(
      parsePlay({ id: uuid(1), kind: "gift", at, item: "treat-fish", message: "  for you  " }),
    ).toEqual({ id: uuid(1), kind: "gift", at, item: "treat-fish", message: "for you" });
  });

  it("refuses a gift with a bad item or note", () => {
    expect(parsePlay({ id: uuid(1), kind: "gift", at, item: "no spaces" })).toBeUndefined();
    expect(parsePlay({ id: uuid(1), kind: "gift", at })).toBeUndefined();
    const long = "a".repeat(MAX_GIFT_MESSAGE + 1);
    expect(
      parsePlay({ id: uuid(1), kind: "gift", at, item: "treat-fish", message: long }),
    ).toBeUndefined();
    expect(
      parsePlay({ id: uuid(1), kind: "gift", at, item: "treat-fish", message: "a\u0007b" }),
    ).toBeUndefined();
  });

  it("reads an opening", () => {
    expect(parsePlay({ id: uuid(2), kind: "gift-opened", at, gift: uuid(1) })).toEqual({
      id: uuid(2),
      kind: "gift-opened",
      at,
      gift: uuid(1),
    });
    expect(parsePlay({ id: uuid(2), kind: "gift-opened", at, gift: "x" })).toBeUndefined();
  });
});

describe("gifts in the room", () => {
  it("hands a gift and its note to the partner at once", async () => {
    const a = await connect("GFTNWZ2345", alice);
    const b = await connect("GFTNWZ2345", bob);
    await a.sendAcked({
      type: "play",
      kind: "gift",
      id: uuid(10),
      at,
      item: "furniture-mouse",
      message: "for the little one",
    });
    await b.waitFor((f) => gifts(f).length === 1, "the gift");
    expect(gifts(b.frames)[0]).toEqual({
      type: "gift",
      id: uuid(10),
      item: "furniture-mouse",
      message: "for the little one",
    });
    expect(gifts(a.frames)).toHaveLength(0);

    await b.sendAcked({ type: "play", kind: "gift-opened", id: uuid(11), at, gift: uuid(10) });
    await a.waitFor((f) => f.some((x) => x["type"] === "gift-opened"), "the opening");
    expect(a.frames.find((x) => x["type"] === "gift-opened")).toEqual({
      type: "gift-opened",
      id: uuid(10),
    });
  });

  it("keeps a gift for a partner who is away, and gives it once", async () => {
    const code = "GFTAWAY234";
    const a = await connect(code, alice);
    const first = await connect(code, bob);
    first.socket.close(1000);
    await a.waitFor(
      (f) => f.some((x) => x["type"] === "room" && x["partnerPresent"] === false),
      "bob leaving",
    );
    const gift = { type: "play", kind: "gift", id: uuid(20), at, item: "treat-fish" };
    await a.sendAcked(gift);
    // Sent again after a reconnect: the room counts it once.
    await a.sendAcked(gift);

    const b = await connect(code, bob);
    expect(gifts(b.frames)).toEqual([{ type: "gift", id: uuid(20), item: "treat-fish" }]);
    b.socket.close(1000);
    const again = await connect(code, bob);
    expect(gifts(again.frames)).toHaveLength(0);
  });
});
