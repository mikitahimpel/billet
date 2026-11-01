import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import type { DemoRoom } from "../src/demo-room-durable-object.ts";
import { routeDemo } from "../src/demo-route.ts";
import {
  MAX_REACTIONS,
  dayOf,
  keepFirstName,
  parseName,
  parsePlay,
  recordReaction,
  recordTreat,
} from "../src/demo-play.ts";

const { DEMO_ROOM } = env as unknown as { DEMO_ROOM: DurableObjectNamespace<DemoRoom> };

const alice = "11111111-1111-4111-8111-111111111111";
const bob = "22222222-2222-4222-8222-222222222222";
const uuid = (n: number) => `aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12, "0")}`;

const connect = async (code: string, device: string) => {
  const response = await routeDemo(
    new Request(`https://host/demo/rooms/${code}/socket?device=${device}`, {
      headers: { Upgrade: "websocket" },
    }),
    DEMO_ROOM,
  )!;
  const socket = response.webSocket!;
  const frames: Array<Record<string, unknown>> = [];
  socket.accept();
  socket.addEventListener("message", (event) => {
    frames.push(JSON.parse(event.data as string));
  });
  return { socket, frames };
};

const settle = () => new Promise((resolve) => setTimeout(resolve, 50));
const play = (id: string, kind: string, at: string) =>
  JSON.stringify({ type: "play", id, kind, at });
const ofType = (frames: Array<Record<string, unknown>>, type: string) =>
  frames.filter((f) => f["type"] === type);

describe("play frame parsing", () => {
  it("accepts pet and treat with an offset time", () => {
    const at = "2026-11-01T23:30:00+01:00";
    expect(parsePlay({ id: uuid(1), kind: "pet", at })).toEqual({ id: uuid(1), kind: "pet", at });
    expect(parsePlay({ id: uuid(1), kind: "treat", at })?.kind).toBe("treat");
  });

  it("rejects an unknown kind, a bad id, or a time without an offset", () => {
    const at = "2026-11-01T10:00:00Z";
    expect(parsePlay({ id: uuid(1), kind: "coin", at })).toBeUndefined();
    expect(parsePlay({ id: "x", kind: "pet", at })).toBeUndefined();
    expect(parsePlay({ id: uuid(1), kind: "pet", at: "2026-11-01T10:00:00" })).toBeUndefined();
    expect(parsePlay({ id: uuid(1), kind: "pet", at: "2026-13-45T10:00:00Z" })).toBeUndefined();
  });
});

describe("treat ledger", () => {
  it("uses the sender's own calendar day, so a late-night treat stays on that day", () => {
    expect(dayOf("2026-11-01T23:59:00+01:00")).toBe("2026-11-01");
    expect(dayOf("2026-11-02T00:01:00+01:00")).toBe("2026-11-02");
  });

  it("keeps one entry per device per day", () => {
    const once = recordTreat({}, alice, "2026-11-01T09:00:00+01:00");
    const twice = recordTreat(once, alice, "2026-11-01T20:00:00+01:00");
    expect(twice).toEqual({ "2026-11-01": [alice] });
    expect(recordTreat(twice, bob, "2026-11-01T21:00:00+01:00")["2026-11-01"]).toEqual([
      alice,
      bob,
    ]);
  });

  it("drops the oldest days beyond the cap", () => {
    let days = {};
    for (let d = 1; d <= 95; d++) {
      const date = new Date(Date.UTC(2026, 0, d)).toISOString().slice(0, 10);
      days = recordTreat(days, alice, `${date}T10:00:00Z`);
    }
    expect(Object.keys(days)).toHaveLength(90);
    expect(days).not.toHaveProperty("2026-01-01");
  });
});

describe("demo room play", () => {
  it("relays a pet live and acks the sender", async () => {
    const a = await connect("PETPASS234", alice);
    const b = await connect("PETPASS234", bob);
    a.socket.send(play(uuid(1), "pet", "2026-11-01T10:00:00+01:00"));
    await settle();
    expect(ofType(a.frames, "ack")).toContainEqual({ type: "ack", id: uuid(1) });
    expect(ofType(b.frames, "play")).toContainEqual({
      type: "play",
      id: uuid(1),
      kind: "pet",
      at: "2026-11-01T10:00:00+01:00",
      from: alice,
    });
  });

  it("replays a pet once when the partner opens the app later", async () => {
    const a = await connect("PETSTAY234", alice);
    const first = await connect("PETSTAY234", bob);
    first.socket.close(1000);
    await settle();
    a.socket.send(play(uuid(2), "pet", "2026-11-01T10:00:00+01:00"));
    await settle();
    const again = await connect("PETSTAY234", bob);
    await settle();
    expect(ofType(again.frames, "play")).toHaveLength(1);
    again.socket.close(1000);
    await settle();
    const third = await connect("PETSTAY234", bob);
    await settle();
    expect(ofType(third.frames, "play")).toEqual([]);
  });

  it("ignores a repeated pet id", async () => {
    const a = await connect("PETSAMEK23", alice);
    const b = await connect("PETSAMEK23", bob);
    for (let i = 0; i < 2; i++) a.socket.send(play(uuid(3), "pet", "2026-11-01T10:00:00Z"));
    await settle();
    expect(ofType(b.frames, "play")).toHaveLength(1);
  });

  it("shares each treat with both phones and counts a device once per day", async () => {
    const code = "TREATSYNC3";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    a.socket.send(play(uuid(4), "treat", "2026-11-01T09:00:00+01:00"));
    a.socket.send(play(uuid(5), "treat", "2026-11-01T18:00:00+01:00"));
    await settle();
    expect(ofType(b.frames, "treats").at(-1)).toEqual({
      type: "treats",
      days: { "2026-11-01": [alice] },
    });
    b.socket.send(play(uuid(6), "treat", "2026-11-01T19:00:00+01:00"));
    await settle();
    const expected = { type: "treats", days: { "2026-11-01": [alice, bob] } };
    expect(ofType(a.frames, "treats").at(-1)).toEqual(expected);
    expect(ofType(b.frames, "treats").at(-1)).toEqual(expected);
  });

  it("keeps treat days across a reconnect and a day boundary", async () => {
    const code = "TREATRESYN";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    a.socket.send(play(uuid(7), "treat", "2026-11-01T23:50:00+01:00"));
    b.socket.send(play(uuid(8), "treat", "2026-11-02T00:10:00+01:00"));
    await settle();
    a.socket.close(1000);
    b.socket.close(1000);
    await settle();
    const back = await connect(code, alice);
    await settle();
    expect(ofType(back.frames, "treats")).toEqual([
      { type: "treats", days: { "2026-11-01": [alice], "2026-11-02": [bob] } },
    ]);
  });

  it("drops a malformed play frame without an ack", async () => {
    const a = await connect("PAPERBAD34", alice);
    a.socket.send(play(uuid(9), "coin", "2026-11-01T10:00:00Z"));
    await settle();
    expect(ofType(a.frames, "ack")).toEqual([]);
  });
});

const at = "2026-11-01T10:00:00+01:00";
const nameFrame = (id: string, name: unknown) =>
  JSON.stringify({ type: "play", id, kind: "name", at, name });
const reactFrame = (id: string, note: string, reaction: unknown) =>
  JSON.stringify({ type: "play", id, kind: "react", at, note, reaction });
const noteFrame = (id: string) => JSON.stringify({ type: "note", id, ink: "x" });

describe("name and reaction parsing", () => {
  it("trims a name and keeps emoji whole", () => {
    expect(parseName("  Mochi ")).toBe("Mochi");
    expect(parseName("🐈".repeat(24))).toBe("🐈".repeat(24));
  });

  it("rejects an empty, too long or control-character name", () => {
    expect(parseName("   ")).toBeUndefined();
    expect(parseName("x".repeat(25))).toBeUndefined();
    expect(parseName("a\nb")).toBeUndefined();
    expect(parseName(7)).toBeUndefined();
  });

  it("reads a name frame and a react frame", () => {
    expect(parsePlay({ id: uuid(1), kind: "name", at, name: " Mochi " })).toEqual({
      id: uuid(1),
      kind: "name",
      at,
      name: "Mochi",
    });
    expect(
      parsePlay({ id: uuid(1), kind: "react", at, note: uuid(2).toUpperCase(), reaction: "stamp" }),
    ).toEqual({ id: uuid(1), kind: "react", at, note: uuid(2), reaction: "stamp" });
  });

  it("rejects a react frame with a bad note or reaction", () => {
    expect(parsePlay({ id: uuid(1), kind: "react", at, note: "x", reaction: "heart" })).toBe(
      undefined,
    );
    expect(parsePlay({ id: uuid(1), kind: "react", at, note: uuid(2), reaction: "coin" })).toBe(
      undefined,
    );
    expect(parsePlay({ id: uuid(1), kind: "name", at })).toBeUndefined();
  });
});

describe("name and reaction rules", () => {
  it("keeps the first name", () => {
    expect(keepFirstName(undefined, "Mochi")).toBe("Mochi");
    expect(keepFirstName("Mochi", "Biscuit")).toBe("Mochi");
  });

  it("replaces a reaction on the same note and drops the oldest past the cap", () => {
    const first = recordReaction({}, uuid(1), "heart");
    expect(recordReaction(first, uuid(1), "stamp")).toEqual({ [uuid(1)]: "stamp" });
    let table = {};
    for (let n = 1; n <= MAX_REACTIONS + 5; n++) table = recordReaction(table, uuid(n), "heart");
    expect(Object.keys(table)).toHaveLength(MAX_REACTIONS);
    expect(table).not.toHaveProperty(uuid(1));
  });
});

describe("demo room name", () => {
  it("shows the first name to both phones and ignores a later one", async () => {
    const code = "NAMEKEEP23";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    a.socket.send(nameFrame(uuid(20), "Mochi"));
    await settle();
    b.socket.send(nameFrame(uuid(21), "Biscuit"));
    await settle();
    expect(ofType(a.frames, "name")).toEqual([
      { type: "name", name: "Mochi" },
      { type: "name", name: "Mochi" },
    ]);
    expect(ofType(b.frames, "name").at(-1)).toEqual({ type: "name", name: "Mochi" });
    expect(ofType(b.frames, "ack")).toContainEqual({ type: "ack", id: uuid(21) });
  });

  it("tells a phone that connects later", async () => {
    const code = "NAMEBACK23";
    const a = await connect(code, alice);
    a.socket.send(nameFrame(uuid(22), "Mochi"));
    await settle();
    a.socket.close(1000);
    await settle();
    const back = await connect(code, alice);
    await settle();
    expect(ofType(back.frames, "name")).toEqual([{ type: "name", name: "Mochi" }]);
  });

  it("drops an invalid name without an ack", async () => {
    const a = await connect("NAMEBAD234", alice);
    a.socket.send(nameFrame(uuid(23), "x".repeat(25)));
    await settle();
    expect(ofType(a.frames, "ack")).toEqual([]);
    expect(ofType(a.frames, "name")).toEqual([]);
  });
});

describe("demo room reactions", () => {
  it("shows a reaction to both phones when the receiver reacts", async () => {
    const code = "REACTWEB23";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    a.socket.send(noteFrame(uuid(30)));
    await settle();
    b.socket.send(reactFrame(uuid(31), uuid(30), "heart"));
    await settle();
    const expected = { type: "reactions", reactions: { [uuid(30)]: "heart" } };
    expect(ofType(a.frames, "reactions")).toEqual([expected]);
    expect(ofType(b.frames, "reactions")).toEqual([expected]);
    b.socket.send(reactFrame(uuid(32), uuid(30), "stamp"));
    await settle();
    expect(ofType(a.frames, "reactions").at(-1)).toEqual({
      type: "reactions",
      reactions: { [uuid(30)]: "stamp" },
    });
  });

  it("ignores a reaction from the sender of the note, or to an unknown note", async () => {
    const code = "REACTSEK23";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    a.socket.send(noteFrame(uuid(33)));
    await settle();
    a.socket.send(reactFrame(uuid(34), uuid(33), "heart"));
    b.socket.send(reactFrame(uuid(35), uuid(36), "heart"));
    await settle();
    expect(ofType(a.frames, "reactions")).toEqual([]);
    expect(ofType(b.frames, "reactions")).toEqual([]);
  });

  it("replays reactions to a phone that connects later", async () => {
    const code = "REACTAGAN3";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    a.socket.send(noteFrame(uuid(37)));
    await settle();
    b.socket.send(reactFrame(uuid(38), uuid(37), "stamp"));
    await settle();
    a.socket.close(1000);
    await settle();
    const back = await connect(code, alice);
    await settle();
    expect(ofType(back.frames, "reactions")).toEqual([
      { type: "reactions", reactions: { [uuid(37)]: "stamp" } },
    ]);
  });
});
