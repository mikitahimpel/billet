import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import type { DemoRoom } from "../src/demo-room-durable-object.ts";
import { routeDemo } from "../src/demo-route.ts";
import { waitFor } from "./demo-wait.ts";
import {
  MAX_LIFE_EVENTS,
  MAX_REACTIONS,
  dayOf,
  keepFirstName,
  parseName,
  parsePlay,
  recordLife,
  recordReaction,
  recordTreat,
  type LifeEvent,
} from "../src/demo-play.ts";

const { DEMO_ROOM } = env as unknown as {
  DEMO_ROOM: DurableObjectNamespace<DemoRoom>;
};

const alice = "11111111-1111-4111-8111-111111111111";
const bob = "22222222-2222-4222-8222-222222222222";
const uuid = (n: number) => `aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12, "0")}`;

type Frame = Record<string, unknown>;

interface Peer {
  readonly socket: WebSocket;
  readonly frames: Frame[];
  /** Sends a frame and waits for the server's ack of `id`. */
  readonly sendAcked: (frame: string, id: string) => Promise<void>;
  readonly waitFor: (check: (frames: Frame[]) => boolean, what: string) => Promise<void>;
}

/** Connects and returns once the server's `room` frame has arrived: replays are sent before it. */
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
    sendAcked: async (frame, id) => {
      socket.send(frame);
      await waitFor(
        () => frames.some((f) => f["type"] === "ack" && f["id"] === id),
        `ack of ${id}`,
      );
    },
  };
  await peer.waitFor((f) => f.some((x) => x["type"] === "room"), "the room frame");
  return peer;
};

/** Closes `peer` and waits until `partner` is told it left, so the server has seen the close. */
const leave = async (peer: Peer, partner: Peer): Promise<void> => {
  const before = partner.frames.length;
  peer.socket.close(1000);
  await partner.waitFor(
    (f) => f.slice(before).some((x) => x["type"] === "room" && x["partnerPresent"] === false),
    "the partner leaving",
  );
};

const play = (id: string, kind: string, at: string) =>
  JSON.stringify({ type: "play", id, kind, at });
const ofType = (frames: Array<Record<string, unknown>>, type: string) =>
  frames.filter((f) => f["type"] === type);

describe("play frame parsing", () => {
  it("accepts pet and treat with an offset time", () => {
    const at = "2026-11-01T23:30:00+01:00";
    expect(parsePlay({ id: uuid(1), kind: "pet", at })).toEqual({
      id: uuid(1),
      kind: "pet",
      at,
    });
    expect(parsePlay({ id: uuid(1), kind: "treat", at })?.kind).toBe("treat");
  });

  it("accepts the life plays: feeding, a game, bedtime and a shoo", () => {
    const at = "2026-11-01T23:30:00+01:00";
    for (const kind of ["feed", "play", "sleep", "shoo"]) {
      expect(parsePlay({ id: uuid(1), kind, at })).toEqual({
        id: uuid(1),
        kind,
        at,
      });
    }
  });

  it("accepts a press of the light switch at on, cosy or off, and nothing else", () => {
    const at = "2026-11-04T22:15:00+01:00";
    for (const light of ["on", "cosy", "off"]) {
      expect(parsePlay({ id: uuid(1), kind: "light", at, light })).toEqual({
        id: uuid(1),
        kind: "light",
        at,
        light,
      });
    }
    expect(parsePlay({ id: uuid(1), kind: "light", at, light: "dim" })).toBeUndefined();
    expect(parsePlay({ id: uuid(1), kind: "light", at })).toBeUndefined();
  });

  it("accepts a room style of known parts given by name, and nothing else", () => {
    const at = "2026-11-04T22:15:00+01:00";
    const style = { wall: "sage", floor: "herringbone", curtains: "linen", drape: "half" };
    expect(parsePlay({ id: uuid(1), kind: "style", at, style })).toEqual({
      id: uuid(1),
      kind: "style",
      at,
      style,
    });
    expect(parsePlay({ id: uuid(1), kind: "style", at, style: {} })).toEqual({
      id: uuid(1),
      kind: "style",
      at,
      style: {},
    });
    for (const bad of [
      undefined,
      "sage",
      ["sage"],
      { ceiling: "sage" },
      { wall: 3 },
      { wall: "sage; drop" },
      { wall: "x".repeat(33) },
    ]) {
      expect(parsePlay({ id: uuid(1), kind: "style", at, style: bad })).toBeUndefined();
    }
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

describe("life log", () => {
  const event = (n: number, at: string): LifeEvent => ({
    id: uuid(n),
    kind: "pet",
    by: alice,
    at,
  });

  it("keeps events in time order and ignores a repeated id", () => {
    const log = recordLife([event(1, "2026-11-01T10:00:00Z")], event(2, "2026-11-01T09:00:00Z"));
    expect(log.map((e) => e.id)).toEqual([uuid(2), uuid(1)]);
    expect(recordLife(log, event(1, "2026-11-01T11:00:00Z"))).toBe(log);
  });

  it("drops the oldest past the cap", () => {
    let log: readonly LifeEvent[] = [];
    for (let n = 0; n < MAX_LIFE_EVENTS + 5; n++) {
      log = recordLife(log, event(n, new Date(Date.UTC(2026, 10, 1, 0, n)).toISOString()));
    }
    expect(log).toHaveLength(MAX_LIFE_EVENTS);
    expect(log[0]?.id).toBe(uuid(5));
  });
});

describe("demo room play", () => {
  it("relays a pet live and acks the sender", async () => {
    const a = await connect("PETPASS234", alice);
    const b = await connect("PETPASS234", bob);
    await a.sendAcked(play(uuid(1), "pet", "2026-11-01T10:00:00+01:00"), uuid(1));
    await b.waitFor((f) => ofType(f, "play").length === 1, "the pet on the partner");
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
    await leave(first, a);
    await a.sendAcked(play(uuid(2), "pet", "2026-11-01T10:00:00+01:00"), uuid(2));
    const again = await connect("PETSTAY234", bob);
    expect(ofType(again.frames, "play")).toHaveLength(1);
    await leave(again, a);
    const third = await connect("PETSTAY234", bob);
    expect(ofType(third.frames, "play")).toEqual([]);
  });

  it("ignores a repeated pet id", async () => {
    const a = await connect("PETSAMEK23", alice);
    const b = await connect("PETSAMEK23", bob);
    await a.sendAcked(play(uuid(3), "pet", "2026-11-01T10:00:00Z"), uuid(3));
    await a.sendAcked(play(uuid(3), "pet", "2026-11-01T10:00:00Z"), uuid(3));
    await a.sendAcked(play(uuid(10), "pet", "2026-11-01T10:00:00Z"), uuid(10));
    await b.waitFor((f) => ofType(f, "play").some((x) => x["id"] === uuid(10)), "the later pet");
    expect(ofType(b.frames, "play").filter((x) => x["id"] === uuid(3))).toHaveLength(1);
  });

  it("shares each treat with both phones and counts a device once per day", async () => {
    const code = "TREATSYNC3";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    await a.sendAcked(play(uuid(4), "treat", "2026-11-01T09:00:00+01:00"), uuid(4));
    await a.sendAcked(play(uuid(5), "treat", "2026-11-01T18:00:00+01:00"), uuid(5));
    await b.waitFor((f) => ofType(f, "treats").length >= 3, "two treat updates on the partner");
    expect(ofType(b.frames, "treats").at(-1)).toEqual({
      type: "treats",
      days: { "2026-11-01": [alice] },
    });
    await b.sendAcked(play(uuid(6), "treat", "2026-11-01T19:00:00+01:00"), uuid(6));
    const expected = { type: "treats", days: { "2026-11-01": [alice, bob] } };
    await a.waitFor(
      (f) =>
        ofType(f, "treats").at(-1)?.["days"] !== undefined &&
        JSON.stringify(ofType(f, "treats").at(-1)) === JSON.stringify(expected),
      "both treats on A",
    );
    expect(ofType(a.frames, "treats").at(-1)).toEqual(expected);
    await b.waitFor(
      (f) => JSON.stringify(ofType(f, "treats").at(-1)) === JSON.stringify(expected),
      "both treats on B",
    );
  });

  it("keeps treat days across a reconnect and a day boundary", async () => {
    const code = "TREATRESYN";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    await a.sendAcked(play(uuid(7), "treat", "2026-11-01T23:50:00+01:00"), uuid(7));
    await b.sendAcked(play(uuid(8), "treat", "2026-11-02T00:10:00+01:00"), uuid(8));
    await leave(a, b);
    const back = await connect(code, alice);
    expect(ofType(back.frames, "treats")).toEqual([
      { type: "treats", days: { "2026-11-01": [alice], "2026-11-02": [bob] } },
    ]);
  });

  it("shares the cat's life with both phones and replays it on connect", async () => {
    const code = "KATSYNC234";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    await a.sendAcked(play(uuid(12), "pet", "2026-11-01T10:00:00+01:00"), uuid(12));
    await b.sendAcked(play(uuid(13), "feed", "2026-11-01T10:05:00+01:00"), uuid(13));
    await a.sendAcked(
      JSON.stringify({
        type: "note",
        id: uuid(14),
        ink: "x",
        at: "2026-11-01T10:06:00+01:00",
      }),
      uuid(14),
    );
    await a.sendAcked(play(uuid(15), "treat", "2026-11-01T10:07:00+01:00"), uuid(15));
    const expected = [
      { id: uuid(12), kind: "pet", by: alice, at: "2026-11-01T10:00:00+01:00" },
      { id: uuid(13), kind: "feed", by: bob, at: "2026-11-01T10:05:00+01:00" },
      {
        id: uuid(14),
        kind: "note",
        by: alice,
        at: "2026-11-01T10:06:00+01:00",
      },
    ];
    const events = (frames: Frame[]) => ofType(frames, "life").flatMap((f) => f["events"]);
    await b.waitFor((f) => events(f).length === 3, "three life events on B");
    await a.waitFor((f) => events(f).length === 3, "three life events on A");
    expect(events(a.frames)).toEqual(expected);
    expect(events(b.frames)).toEqual(expected);
    await leave(a, b);
    const back = await connect(code, alice);
    expect(ofType(back.frames, "life")).toEqual([{ type: "life", events: expected }]);
  });

  it("drops a malformed play frame without an ack", async () => {
    const a = await connect("PAPERBAD34", alice);
    a.socket.send(play(uuid(9), "coin", "2026-11-01T10:00:00Z"));
    await a.sendAcked(play(uuid(11), "pet", "2026-11-01T10:00:00Z"), uuid(11));
    expect(ofType(a.frames, "ack")).toEqual([{ type: "ack", id: uuid(11) }]);
  });
});

const playsURL = (code: string, device: string) =>
  `https://host/demo/rooms/${code}/plays?device=${device}`;
const postPlays = (code: string, device: string, body: unknown) =>
  routeDemo(
    new Request(playsURL(code, device), { method: "POST", body: JSON.stringify(body) }),
    DEMO_ROOM,
  )!;
const playBody = (id: string, kind: string, when: string) => ({ type: "play", id, kind, at: when });

describe("demo room plays posted by a widget", () => {
  it("relays a posted pet to the partner and keeps it in the cat's life", async () => {
    const code = "WPETRAYS23";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    const response = await postPlays(code, alice, [
      playBody(uuid(20), "pet", "2026-11-01T10:00:00+01:00"),
    ]);
    expect(response.status).toBe(204);
    await b.waitFor((f) => ofType(f, "play").length === 1, "the pet on the partner");
    expect(ofType(b.frames, "play")).toEqual([
      { type: "play", id: uuid(20), kind: "pet", at: "2026-11-01T10:00:00+01:00", from: alice },
    ]);
    await a.waitFor((f) => ofType(f, "life").length === 1, "the pet in A's life");
  });

  it("leaves the sender's queued notes and pets for its app", async () => {
    const code = "WKEEPQ2345";
    const a = await connect(code, alice);
    const first = await connect(code, bob);
    await leave(first, a);
    await a.sendAcked(play(uuid(21), "pet", "2026-11-01T10:00:00+01:00"), uuid(21));
    const posted = await postPlays(code, bob, [
      playBody(uuid(22), "treat", "2026-11-01T11:00:00+01:00"),
      playBody(uuid(23), "feed", "2026-11-01T11:00:00+01:00"),
    ]);
    expect(posted.status).toBe(204);
    const back = await connect(code, bob);
    expect(ofType(back.frames, "play")).toEqual([
      { type: "play", id: uuid(21), kind: "pet", at: "2026-11-01T10:00:00+01:00", from: alice },
    ]);
    expect(ofType(back.frames, "treats")).toEqual([
      { type: "treats", days: { "2026-11-01": [bob] } },
    ]);
    const kinds = ofType(back.frames, "life").flatMap((f) =>
      (f["events"] as Frame[]).map((e) => e["kind"]),
    );
    expect(kinds).toEqual(["pet", "feed"]);
  });

  it("refuses a device that is not in the room", async () => {
    const code = "WSTRANGE23";
    await connect(code, alice);
    const response = await postPlays(code, bob, [
      playBody(uuid(24), "pet", "2026-11-01T10:00:00+01:00"),
    ]);
    expect(response.status).toBe(404);
  });

  it("refuses other kinds, too many plays, a bad frame and a GET", async () => {
    const code = "WBADPAST23";
    await connect(code, alice);
    const when = "2026-11-01T10:00:00+01:00";
    const pet = playBody(uuid(25), "pet", when);
    const refused = [
      [{ ...playBody(uuid(26), "rename", when), name: "Mochi" }],
      [pet, pet, pet],
      [],
      [{ ...pet, at: "yesterday" }],
      { plays: [pet] },
    ];
    for (const body of refused) {
      expect((await postPlays(code, alice, body)).status).toBe(400);
    }
    const get = await routeDemo(new Request(playsURL(code, alice)), DEMO_ROOM)!;
    expect(get.status).toBe(400);
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
      parsePlay({
        id: uuid(1),
        kind: "react",
        at,
        note: uuid(2).toUpperCase(),
        reaction: "stamp",
      }),
    ).toEqual({
      id: uuid(1),
      kind: "react",
      at,
      note: uuid(2),
      reaction: "stamp",
    });
  });

  it("rejects a react frame with a bad note or reaction", () => {
    expect(
      parsePlay({
        id: uuid(1),
        kind: "react",
        at,
        note: "x",
        reaction: "heart",
      }),
    ).toBe(undefined);
    expect(
      parsePlay({
        id: uuid(1),
        kind: "react",
        at,
        note: uuid(2),
        reaction: "coin",
      }),
    ).toBe(undefined);
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
    expect(recordReaction(first, uuid(1), "stamp")).toEqual({
      [uuid(1)]: "stamp",
    });
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
    await a.sendAcked(nameFrame(uuid(20), "Mochi"), uuid(20));
    await b.sendAcked(nameFrame(uuid(21), "Biscuit"), uuid(21));
    await a.waitFor((f) => ofType(f, "name").length === 2, "both name broadcasts on A");
    expect(ofType(a.frames, "name")).toEqual([
      { type: "name", name: "Mochi" },
      { type: "name", name: "Mochi" },
    ]);
    expect(ofType(b.frames, "name").at(-1)).toEqual({
      type: "name",
      name: "Mochi",
    });
  });

  it("tells a phone that connects later", async () => {
    const code = "NAMEBACK23";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    await a.sendAcked(nameFrame(uuid(22), "Mochi"), uuid(22));
    await leave(a, b);
    const back = await connect(code, alice);
    expect(ofType(back.frames, "name")).toEqual([{ type: "name", name: "Mochi" }]);
  });

  it("drops an invalid name without an ack", async () => {
    const a = await connect("NAMEBAD234", alice);
    a.socket.send(nameFrame(uuid(23), "x".repeat(25)));
    await a.sendAcked(play(uuid(24), "pet", at), uuid(24));
    expect(ofType(a.frames, "ack")).toEqual([{ type: "ack", id: uuid(24) }]);
    expect(ofType(a.frames, "name")).toEqual([]);
  });
});

describe("demo room reactions", () => {
  const reactions = (id: string, value: string) => ({
    type: "reactions",
    reactions: { [id]: value },
  });
  const lastReactions = (frames: Frame[]) => JSON.stringify(ofType(frames, "reactions").at(-1));

  it("shows a reaction to both phones when the receiver reacts", async () => {
    const code = "REACTWEB23";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    await a.sendAcked(noteFrame(uuid(30)), uuid(30));
    await b.sendAcked(reactFrame(uuid(31), uuid(30), "heart"), uuid(31));
    const heart = reactions(uuid(30), "heart");
    await a.waitFor((f) => lastReactions(f) === JSON.stringify(heart), "the heart on A");
    await b.waitFor((f) => lastReactions(f) === JSON.stringify(heart), "the heart on B");
    expect(ofType(a.frames, "reactions")).toEqual([heart]);
    expect(ofType(b.frames, "reactions")).toEqual([heart]);
    await b.sendAcked(reactFrame(uuid(32), uuid(30), "stamp"), uuid(32));
    const stamp = reactions(uuid(30), "stamp");
    await a.waitFor((f) => lastReactions(f) === JSON.stringify(stamp), "the stamp on A");
  });

  it("ignores a reaction from the sender of the note, or to an unknown note", async () => {
    const code = "REACTSEK23";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    await a.sendAcked(noteFrame(uuid(33)), uuid(33));
    await a.sendAcked(reactFrame(uuid(34), uuid(33), "heart"), uuid(34));
    await b.sendAcked(reactFrame(uuid(35), uuid(36), "heart"), uuid(35));
    expect(ofType(a.frames, "reactions")).toEqual([]);
    expect(ofType(b.frames, "reactions")).toEqual([]);
  });

  it("replays reactions to a phone that connects later", async () => {
    const code = "REACTAGAN3";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    await a.sendAcked(noteFrame(uuid(37)), uuid(37));
    await b.sendAcked(reactFrame(uuid(38), uuid(37), "stamp"), uuid(38));
    await leave(a, b);
    const back = await connect(code, alice);
    expect(ofType(back.frames, "reactions")).toEqual([reactions(uuid(37), "stamp")]);
  });
});

const adoptPlay = (id: string, fields: Record<string, unknown>) =>
  JSON.stringify({ type: "play", id, kind: "adopt", at, ...fields });

describe("choosing the cat together", () => {
  it("parses picks, holds and adoptions and drops anything else", () => {
    const frame = (fields: Record<string, unknown>) => ({
      type: "play",
      id: uuid(1),
      kind: "adopt",
      at,
      ...fields,
    });
    expect(parsePlay(frame({ move: "pick", cat: "ginger" }))).toMatchObject({
      cat: "ginger",
    });
    expect(parsePlay(frame({ move: "pick", cat: null }))).toMatchObject({
      cat: null,
    });
    expect(parsePlay(frame({ move: "hold", holding: true }))).toMatchObject({
      holding: true,
    });
    expect(parsePlay(frame({ move: "adopt", cat: "fluffy" }))).toMatchObject({
      cat: "fluffy",
    });
    expect(parsePlay(frame({ move: "pick", cat: "tiger" }))).toBeUndefined();
    expect(parsePlay(frame({ move: "hold" }))).toBeUndefined();
    expect(parsePlay(frame({ move: "adopt", cat: null }))).toBeUndefined();
    expect(parsePlay(frame({ move: "dance" }))).toBeUndefined();
  });

  it("relays moves to the partner and not back to the sender", async () => {
    const a = await connect("PAWSNEWS23", alice);
    const b = await connect("PAWSNEWS23", bob);
    await a.sendAcked(adoptPlay(uuid(21), { move: "pick", cat: "black" }), uuid(21));
    await a.sendAcked(adoptPlay(uuid(22), { move: "hold", holding: true }), uuid(22));
    await b.waitFor((f) => ofType(f, "adopt").length === 2, "two moves");
    expect(ofType(b.frames, "adopt")).toEqual([
      { type: "adopt", id: uuid(21), move: "pick", cat: "black" },
      { type: "adopt", id: uuid(22), move: "hold", holding: true },
    ]);
    expect(ofType(a.frames, "adopt")).toEqual([]);
  });

  it("replays the partner's latest pick and the adoption on connect", async () => {
    const a = await connect("PAWSBACK34", alice);
    await a.sendAcked(adoptPlay(uuid(31), { move: "pick", cat: "kitten" }), uuid(31));
    await a.sendAcked(adoptPlay(uuid(32), { move: "pick", cat: "ginger" }), uuid(32));
    await a.sendAcked(adoptPlay(uuid(33), { move: "hold", holding: true }), uuid(33));
    const b = await connect("PAWSBACK34", bob);
    expect(ofType(b.frames, "adopt")).toEqual([
      { type: "adopt", id: uuid(32), move: "pick", cat: "ginger" },
    ]);
    await b.sendAcked(adoptPlay(uuid(34), { move: "adopt", cat: "ginger" }), uuid(34));
    await leave(b, a);
    const again = await connect("PAWSBACK34", bob);
    expect(ofType(again.frames, "adopt")).toEqual([
      { type: "adopt", id: uuid(32), move: "pick", cat: "ginger" },
      { type: "adopt", id: uuid(34), move: "adopt", cat: "ginger" },
    ]);
  });

  it("keeps the last press of the light switch from either phone and replays it", async () => {
    const a = await connect("PAWSDARK56", alice);
    const b = await connect("PAWSDARK56", bob);
    const press = (id: string, light: string) =>
      JSON.stringify({ type: "play", id, kind: "light", at, light });
    await a.sendAcked(press(uuid(51), "cosy"), uuid(51));
    await b.waitFor((f) => ofType(f, "light").some((x) => x["light"] === "cosy"), "the press");
    await b.sendAcked(press(uuid(52), "off"), uuid(52));
    await a.waitFor((f) => ofType(f, "light").some((x) => x["light"] === "off"), "the press");
    await leave(b, a);
    const later = await connect("PAWSDARK56", alice);
    expect(ofType(later.frames, "light").at(-1)).toEqual({ type: "light", light: "off" });
  });

  it("keeps the last style from either phone, whole, and replays it", async () => {
    const a = await connect("PAWSDECK57", alice);
    const b = await connect("PAWSDECK57", bob);
    const restyle = (id: string, style: Record<string, string>) =>
      JSON.stringify({ type: "play", id, kind: "style", at, style });
    await a.sendAcked(restyle(uuid(61), { wall: "sage", fairy: "ice" }), uuid(61));
    await b.waitFor(
      (f) => ofType(f, "style").some((x) => JSON.stringify(x["style"]).includes("sage")),
      "the style",
    );
    await b.sendAcked(restyle(uuid(62), { wall: "rose", floor: "tiles" }), uuid(62));
    await a.waitFor(
      (f) => ofType(f, "style").some((x) => JSON.stringify(x["style"]).includes("rose")),
      "the style",
    );
    await leave(b, a);
    const later = await connect("PAWSDECK57", alice);
    expect(ofType(later.frames, "style").at(-1)).toEqual({
      type: "style",
      style: { wall: "rose", floor: "tiles" },
    });
  });

  it("renames the cat over its first name, the last one winning", async () => {
    const a = await connect("PAWSNAME45", alice);
    const b = await connect("PAWSNAME45", bob);
    await a.sendAcked(nameFrame(uuid(41), "Mochi"), uuid(41));
    const rename = (id: string, name: string) =>
      JSON.stringify({ type: "play", id, kind: "rename", at, name });
    await b.sendAcked(rename(uuid(42), "Biscuit"), uuid(42));
    await a.sendAcked(rename(uuid(43), "Pumpkin"), uuid(43));
    await b.waitFor((f) => ofType(f, "name").some((x) => x["name"] === "Pumpkin"), "the rename");
    await leave(b, a);
    const later = await connect("PAWSNAME45", bob);
    expect(ofType(later.frames, "name").at(-1)).toEqual({
      type: "name",
      name: "Pumpkin",
    });
  });
});
