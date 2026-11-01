import { env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import type { DemoRoom } from "../src/demo-room-durable-object.ts";
import { routeDemo } from "../src/demo-route.ts";

const { DEMO_ROOM } = env as unknown as { DEMO_ROOM: DurableObjectNamespace<DemoRoom> };

const CODE = "ABCDEFGH23";
const alice = "11111111-1111-4111-8111-111111111111";
const bob = "22222222-2222-4222-8222-222222222222";
const carol = "33333333-3333-4333-8333-333333333333";
const noteId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

const request = (code: string, device: string) =>
  new Request(`https://host/demo/rooms/${code}/socket?device=${device}`, {
    headers: { Upgrade: "websocket" },
  });

const connect = async (code: string, device: string) => {
  const response = await routeDemo(request(code, device), DEMO_ROOM)!;
  const socket = response.webSocket;
  if (socket === null) return { response, socket: undefined, frames: [] as unknown[] };
  const frames: unknown[] = [];
  socket.accept();
  socket.addEventListener("message", (event) => {
    frames.push(JSON.parse(event.data as string));
  });
  return { response, socket, frames };
};

const settle = () => new Promise((resolve) => setTimeout(resolve, 50));

describe("demo room", () => {
  it("passes a note from one device to the other and acks the sender", async () => {
    const code = "NTEPASS234";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    a.socket!.send(JSON.stringify({ type: "note", id: noteId, ink: "QUJD" }));
    await settle();
    expect(a.frames).toContainEqual({ type: "ack", id: noteId });
    expect(b.frames).toContainEqual({ type: "note", id: noteId, ink: "QUJD", from: alice });
    expect(b.frames).toContainEqual({ type: "room", partnerPresent: true });
  });

  it("refuses a third device with 403", async () => {
    const code = "THRDDEV234";
    await connect(code, alice);
    await connect(code, bob);
    const c = await connect(code, carol);
    expect(c.response.status).toBe(403);
  });

  it("replays a stored note when the partner connects later, once", async () => {
    const code = "RPRAY23456";
    const a = await connect(code, alice);
    const first = await connect(code, bob);
    first.socket!.close(1000);
    await settle();
    a.socket!.send(JSON.stringify({ type: "note", id: noteId, ink: "QUJD" }));
    await settle();
    expect(a.frames).toContainEqual({ type: "ack", id: noteId });
    const again = await connect(code, bob);
    await settle();
    expect(again.frames).toContainEqual({ type: "note", id: noteId, ink: "QUJD", from: alice });
    again.socket!.close(1000);
    await settle();
    const third = await connect(code, bob);
    await settle();
    expect(third.frames.filter((f) => (f as { type: string }).type === "note")).toEqual([]);
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
  const { STUB_DEMO_ROOM } = env as unknown as { STUB_DEMO_ROOM: DurableObjectNamespace<DemoRoom> };
  const token = "ab".repeat(32);
  const code = "PSHTST2345";

  const connectStub = async (device: string) => {
    const response = await routeDemo(request(code, device), STUB_DEMO_ROOM)!;
    const socket = response.webSocket!;
    socket.accept();
    return socket;
  };

  it("sends one APNs alert for a note the partner socket cannot take, and serves the note", async () => {
    const a = await connectStub(alice);
    const b = await connectStub(bob);
    b.send(JSON.stringify({ type: "push-token", token }));
    await settle();
    b.close(1000);
    await settle();
    a.send(JSON.stringify({ type: "note", id: noteId, ink: "QUJD" }));
    await settle();

    const stub = STUB_DEMO_ROOM.get(STUB_DEMO_ROOM.idFromName(code));
    const calls = await runInDurableObject(stub, (_, state) =>
      state.storage.get<{ url: string; headers: Record<string, string>; body: string }[]>(
        "apnsCalls",
      ),
    );
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

    const fetchNote = (device: string, id = noteId) =>
      routeDemo(
        new Request(`https://host/demo/rooms/${code}/notes/${id}?device=${device}`),
        STUB_DEMO_ROOM,
      )!;
    const found = await fetchNote(bob);
    expect(found.status).toBe(200);
    expect(await found.json()).toEqual({ id: noteId, ink: "QUJD", from: alice });
    expect((await fetchNote(bob)).status).toBe(200);
    expect((await fetchNote(alice)).status).toBe(404);
    expect((await fetchNote(carol)).status).toBe(404);

    const again = await connectStub(bob);
    const frames: unknown[] = [];
    again.addEventListener("message", (event) => {
      frames.push(JSON.parse(event.data as string));
    });
    await settle();
    expect(frames).toContainEqual({ type: "note", id: noteId, ink: "QUJD", from: alice });
  });
});

describe("demo ack latency", () => {
  const { HANG_DEMO_ROOM } = env as unknown as { HANG_DEMO_ROOM: DurableObjectNamespace<DemoRoom> };

  it("acks a note for an offline partner even when APNs never answers", async () => {
    const code = "ACKFAST234";
    const open = async (device: string) => {
      const response = await routeDemo(request(code, device), HANG_DEMO_ROOM)!;
      const socket = response.webSocket!;
      const frames: unknown[] = [];
      socket.addEventListener("message", (event) => {
        frames.push(JSON.parse(event.data as string));
      });
      socket.accept();
      return { socket, frames };
    };
    const a = await open(alice);
    const b = await open(bob);
    b.socket.send(JSON.stringify({ type: "push-token", token: "cd".repeat(32) }));
    await settle();
    b.socket.close(1000);
    await settle();
    a.socket.send(JSON.stringify({ type: "note", id: noteId, ink: "QUJD" }));
    await settle();
    expect(a.frames).toContainEqual({ type: "ack", id: noteId });
  });
});
