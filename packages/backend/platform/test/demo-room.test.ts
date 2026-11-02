import { env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import type { DemoRoom } from "../src/demo-room-durable-object.ts";
import { routeDemo } from "../src/demo-route.ts";
import { waitFor } from "./demo-wait.ts";

type Rooms = DurableObjectNamespace<DemoRoom>;
const { DEMO_ROOM, STUB_DEMO_ROOM, HANG_DEMO_ROOM } = env as unknown as {
  DEMO_ROOM: Rooms;
  STUB_DEMO_ROOM: Rooms;
  HANG_DEMO_ROOM: Rooms;
};

const CODE = "ABCDEFGH23";
const alice = "11111111-1111-4111-8111-111111111111";
const bob = "22222222-2222-4222-8222-222222222222";
const carol = "33333333-3333-4333-8333-333333333333";
const noteId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

const request = (code: string, device: string) =>
  new Request(`https://host/demo/rooms/${code}/socket?device=${device}`, {
    headers: { Upgrade: "websocket" },
  });

type Frame = Record<string, unknown>;

interface Peer {
  readonly response: Response;
  readonly socket: WebSocket;
  readonly frames: Frame[];
  readonly waitFor: (check: (frames: Frame[]) => boolean, what: string) => Promise<void>;
}

/** Opens a socket and returns once the server's `room` frame arrived: replays are sent before it. */
const connect = async (code: string, device: string, rooms: Rooms = DEMO_ROOM): Promise<Peer> => {
  const response = await routeDemo(request(code, device), rooms)!;
  const socket = response.webSocket!;
  const frames: Frame[] = [];
  socket.accept();
  socket.addEventListener("message", (event) => {
    frames.push(JSON.parse(event.data as string));
  });
  const peer: Peer = {
    response,
    socket,
    frames,
    waitFor: (check, what) => waitFor(() => check(frames), what),
  };
  await peer.waitFor((f) => f.some((x) => x["type"] === "room"), "the room frame");
  return peer;
};

const leave = async (peer: Peer, partner: Peer): Promise<void> => {
  const before = partner.frames.length;
  peer.socket.close(1000);
  await partner.waitFor(
    (f) => f.slice(before).some((x) => x["type"] === "room" && x["partnerPresent"] === false),
    "the partner leaving",
  );
};

const note = JSON.stringify({ type: "note", id: noteId, ink: "QUJD" });
const hasAck = (frames: Frame[]) => frames.some((f) => f["type"] === "ack" && f["id"] === noteId);
const notes = (frames: Frame[]) => frames.filter((f) => f["type"] === "note");
const delivered = { type: "note", id: noteId, ink: "QUJD", from: alice };

describe("demo room", () => {
  it("passes a note from one device to the other and acks the sender", async () => {
    const a = await connect("NTEPASS234", alice);
    const b = await connect("NTEPASS234", bob);
    a.socket.send(note);
    await a.waitFor(hasAck, "the ack");
    await b.waitFor((f) => notes(f).length === 1, "the note on the partner");
    expect(notes(b.frames)).toEqual([delivered]);
    expect(b.frames).toContainEqual({ type: "room", partnerPresent: true });
  });

  it("refuses a third device with 403", async () => {
    await connect("THRDDEV234", alice);
    await connect("THRDDEV234", bob);
    const response = await routeDemo(request("THRDDEV234", carol), DEMO_ROOM)!;
    expect(response.status).toBe(403);
  });

  it("replays a stored note when the partner connects later, once", async () => {
    const code = "RPRAY23456";
    const a = await connect(code, alice);
    const first = await connect(code, bob);
    await leave(first, a);
    a.socket.send(note);
    await a.waitFor(hasAck, "the ack");
    const again = await connect(code, bob);
    expect(notes(again.frames)).toEqual([delivered]);
    await leave(again, a);
    const third = await connect(code, bob);
    expect(notes(third.frames)).toEqual([]);
  });

  it("rejects a bad code or device with 400", async () => {
    expect((await routeDemo(request("short", alice), DEMO_ROOM)!).status).toBe(400);
    expect((await routeDemo(request(CODE, "nope"), DEMO_ROOM)!).status).toBe(400);
  });
});

describe("demo route outside the dev stage", () => {
  it("answers 404 when the demo room is not bound", async () => {
    const response = await routeDemo(request(CODE, alice), undefined)!;
    expect(response.status).toBe(404);
  });

  it("leaves other paths alone", () => {
    expect(routeDemo(new Request("https://host/"), undefined)).toBeUndefined();
  });
});

describe("demo push and note fetch", () => {
  const token = "ab".repeat(32);
  const code = "PSHTST2345";

  it("sends one APNs alert for a note the partner socket cannot take, and serves the note", async () => {
    const a = await connect(code, alice, STUB_DEMO_ROOM);
    const b = await connect(code, bob, STUB_DEMO_ROOM);
    b.socket.send(JSON.stringify({ type: "push-token", token }));
    // The token has no ack, so the first note the room accepts after it proves it was stored.
    await leave(b, a);
    a.socket.send(note);
    await a.waitFor(hasAck, "the ack");

    const stub = STUB_DEMO_ROOM.get(STUB_DEMO_ROOM.idFromName(code));
    type Call = { url: string; headers: Record<string, string>; body: string };
    const readCalls = () => runInDurableObject(stub, (_, s) => s.storage.get<Call[]>("apnsCalls"));
    let calls: Call[] | undefined;
    for (let i = 0; i < 2000 && (calls = await readCalls()) === undefined; i++) {
      await new Promise((resolve) => setTimeout(resolve, 2));
    }
    expect(calls).toHaveLength(1);
    const call = calls![0]!;
    expect(call.url).toBe(`https://api.push.apple.com/3/device/${token}`);
    expect(call.headers["apns-topic"]).toBe("com.mikitahimpel.billet");
    expect(call.headers["apns-push-type"]).toBe("alert");
    expect(call.headers["authorization"]).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    const payload = JSON.parse(call.body);
    expect(payload.aps["mutable-content"]).toBe(1);
    expect(payload.aps.alert.body).toBe("New note");
    expect(payload.noteURL).toBe(`https://host/demo/rooms/${code}/notes/${noteId}`);
    expect(call.body).not.toContain(token);

    const fetchNote = (device: string) =>
      routeDemo(
        new Request(`https://host/demo/rooms/${code}/notes/${noteId}?device=${device}`),
        STUB_DEMO_ROOM,
      )!;
    const found = await fetchNote(bob);
    expect(found.status).toBe(200);
    expect(await found.json()).toEqual({ id: noteId, ink: "QUJD", from: alice });
    expect((await fetchNote(bob)).status).toBe(200);
    expect((await fetchNote(alice)).status).toBe(404);
    expect((await fetchNote(carol)).status).toBe(404);

    const again = await connect(code, bob, STUB_DEMO_ROOM);
    expect(notes(again.frames)).toEqual([delivered]);
  });
});

describe("demo ack latency", () => {
  it("acks a note for an offline partner even when APNs never answers", async () => {
    const code = "ACKFAST234";
    const a = await connect(code, alice, HANG_DEMO_ROOM);
    const b = await connect(code, bob, HANG_DEMO_ROOM);
    b.socket.send(JSON.stringify({ type: "push-token", token: "cd".repeat(32) }));
    await leave(b, a);
    a.socket.send(note);
    await a.waitFor(hasAck, "the ack while APNs hangs");
  });
});
