import { env } from "cloudflare:workers";
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
