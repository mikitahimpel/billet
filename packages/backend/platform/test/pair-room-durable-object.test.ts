import { env } from "cloudflare:workers";
import { evictDurableObject, runInDurableObject } from "cloudflare:test";
import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { MediaKey, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { ROOM_USER_HEADER, type PairRoom } from "../src/pair-room-durable-object.ts";

const { PAIR_ROOM } = env as unknown as { PAIR_ROOM: DurableObjectNamespace<PairRoom> };

const alice = Schema.decodeUnknownSync(UserId)("user-alice");
const bob = Schema.decodeUnknownSync(UserId)("user-bob");
const mallory = Schema.decodeUnknownSync(UserId)("user-mallory");
const pairId = Schema.decodeUnknownSync(PairId)("pair-1");
const image = Schema.decodeUnknownSync(MediaKey)("pairs/pair-1/notes/note-1.png");
const photo = SendNoteRequest.cases.Photo.make({ image });

const newRoom = () => PAIR_ROOM.get(PAIR_ROOM.newUniqueId());

const openRoom = async () => {
  const room = newRoom();
  await room.open(pairId, [alice, bob]);
  return room;
};

const connect = (room: DurableObjectStub<PairRoom>, headers: Record<string, string>) =>
  room.fetch("https://pair-room/socket", { headers });

const upgrade = (user: string) => ({ Upgrade: "websocket", [ROOM_USER_HEADER]: user });

describe("PairRoom state", () => {
  it("starts vacant and refuses notes until it is opened", async () => {
    const room = newRoom();
    expect(await room.snapshot()).toEqual({ _tag: "Vacant" });
    expect(await room.sendNote(alice, photo)).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "RoomNotOpen" },
    });
  });

  it("opens, and a repeated open changes nothing", async () => {
    const room = await openRoom();
    await room.sendNote(alice, photo);
    await room.open(pairId, [bob, alice]);
    expect(await room.snapshot()).toMatchObject({ _tag: "Active", pairId, lastSeq: 1 });
  });

  it("assigns the id, author and time of a note on the server", async () => {
    const room = await openRoom();
    const before = Date.now();
    await room.sendNote(bob, photo);
    const [entry] = await room.notes(0, 10);
    expect(entry).toMatchObject({ seq: 1, note: { _tag: "Photo", author: bob, image } });
    expect(entry?.note.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(entry?.note.sentAt).toBeGreaterThanOrEqual(before);
  });

  it("round-trips a drawing through SQLite", async () => {
    const room = await openRoom();
    const compact = {
      version: 1,
      strokes: [{ color: "#2A1A1C", width: 3, points: [10, 20, 30, 40] }],
    } as const;
    await room.sendNote(alice, SendNoteRequest.cases.Drawing.make({ compact, image }));
    expect((await room.notes(0, 1))[0]?.note).toMatchObject({ _tag: "Drawing", compact });
  });

  it("orders concurrent notes without gaps or duplicates", async () => {
    const room = await openRoom();
    await Promise.all(Array.from({ length: 25 }, () => room.sendNote(alice, photo)));
    const notes = await room.notes(0, 100);
    expect(notes.map((n) => n.seq)).toEqual(Array.from({ length: 25 }, (_, i) => i + 1));
    expect(new Set(notes.map((n) => n.note.id)).size).toBe(25);
    expect(await room.snapshot()).toMatchObject({ lastSeq: 25 });
  });

  it("pages through notes with a cursor and a limit", async () => {
    const room = await openRoom();
    for (let i = 0; i < 3; i += 1) await room.sendNote(alice, photo);
    expect((await room.notes(1, 1)).map((n) => n.seq)).toEqual([2]);
    expect((await room.notes(3, 10)).map((n) => n.seq)).toEqual([]);
  });

  it("rejects a stranger's note and stores nothing", async () => {
    const room = await openRoom();
    expect(await room.sendNote(mallory, photo)).toMatchObject({
      _tag: "Rejected",
      rejection: { _tag: "NotAMember" },
    });
    expect(await room.notes(0, 10)).toEqual([]);
  });

  it("keeps two rooms apart", async () => {
    const [one, two] = [await openRoom(), await openRoom()];
    await one.sendNote(alice, photo);
    expect(await two.snapshot()).toMatchObject({ lastSeq: 0 });
    expect(await two.notes(0, 10)).toEqual([]);
  });
});

describe("PairRoom storage", () => {
  it("keeps notes, presence and the streak across eviction", async () => {
    const room = await openRoom();
    await room.sendNote(alice, photo);
    await room.setPresence(bob, "drawing");
    await runInDurableObject(room, (_, state) => {
      state.storage.sql.exec("UPDATE room SET streak_days = 4");
    });

    await evictDurableObject(room);

    expect(await room.snapshot()).toEqual({
      _tag: "Active",
      pairId,
      members: [
        { user: alice, presence: "idle" },
        { user: bob, presence: "drawing" },
      ],
      lastSeq: 1,
      streakDays: 4,
    });
    await room.sendNote(bob, photo);
    expect((await room.notes(0, 10)).map((n) => n.seq)).toEqual([1, 2]);
  });

  it("runs each migration once, however often the object wakes", async () => {
    const room = await openRoom();
    await evictDurableObject(room);
    await room.snapshot();
    const names = await runInDurableObject(room, (_, state) =>
      state.storage.sql
        .exec<{ name: string }>("SELECT name FROM __drizzle_migrations ORDER BY name")
        .toArray(),
    );
    expect(names.map(({ name }) => name)).toEqual([
      expect.stringContaining("_init"),
      expect.stringContaining("_pair_room"),
    ]);
  });

  it("rolls the state back if appending the note fails", async () => {
    const room = await openRoom();
    await runInDurableObject(room, (_, state) => {
      state.storage.sql.exec("DROP TABLE note");
    });
    const outcome = await runInDurableObject(room, (instance) =>
      instance.sendNote(alice, photo).then(
        () => "stored",
        () => "failed",
      ),
    );
    expect(outcome).toBe("failed");
    expect(await room.snapshot()).toMatchObject({ lastSeq: 0 });
  });
});

describe("PairRoom sockets", () => {
  it("refuses a plain request", async () => {
    const room = await openRoom();
    expect((await connect(room, {})).status).toBe(426);
  });

  it("refuses an upgrade that names nobody", async () => {
    const room = await openRoom();
    expect((await connect(room, { Upgrade: "websocket" })).status).toBe(400);
  });

  it("refuses a stranger, and everyone in a vacant room", async () => {
    expect((await connect(await openRoom(), upgrade(mallory))).status).toBe(403);
    expect((await connect(newRoom(), upgrade(alice))).status).toBe(403);
  });

  it("accepts a partner's socket through the hibernation API, tagged with the user", async () => {
    const room = await openRoom();
    const response = await connect(room, upgrade(alice));
    expect(response.status).toBe(101);
    response.webSocket?.accept();

    const tags = await runInDurableObject(room, (_, state) =>
      state.getWebSockets().map((socket) => state.getTags(socket)),
    );
    expect(tags).toEqual([[alice]]);
  });

  it("keeps the socket open while the object is evicted", async () => {
    const room = await openRoom();
    const { webSocket } = await connect(room, upgrade(alice));
    webSocket?.accept();

    await evictDurableObject(room);

    expect(webSocket?.readyState).toBe(WebSocket.OPEN);
    const count = await runInDurableObject(room, (_, state) => state.getWebSockets(alice).length);
    expect(count).toBe(1);
  });

  it.each([1006, 1015])("does not throw when a connection ends with %i", async (code) => {
    const room = await openRoom();
    const { webSocket } = await connect(room, upgrade(alice));
    webSocket?.accept();

    await runInDurableObject(room, (instance, state) => {
      const [socket] = state.getWebSockets(alice);
      if (socket === undefined) throw new Error("expected an accepted socket");
      expect(() => {
        instance.webSocketClose(socket, code);
      }).not.toThrow();
    });
  });

  it("completes a close started by the client", async () => {
    const room = await openRoom();
    const { webSocket } = await connect(room, upgrade(alice));
    webSocket?.accept();
    const closed = new Promise<number>((resolve) => {
      webSocket?.addEventListener("close", (event) => {
        resolve(event.code);
      });
    });

    webSocket?.close(1000, "done");

    expect(await closed).toBe(1000);
  });
});

describe("PairRoom notes page", () => {
  const drawing = SendNoteRequest.cases.Photo.make({ image });

  it("skips a note body it cannot decode instead of failing the page", async () => {
    const room = await openRoom();
    await room.sendNote(alice, drawing);
    await room.sendNote(alice, drawing);
    await room.sendNote(bob, drawing);
    await runInDurableObject(room, (_, state) => {
      state.storage.sql.exec("UPDATE note SET body = ? WHERE seq = 2", '{"old":"shape"}');
    });
    const page = await room.notes(0, 10);
    expect(page.map((entry) => entry.seq)).toEqual([1, 3]);
  });

  it("never returns an unbounded page", async () => {
    const room = await openRoom();
    await room.sendNote(alice, drawing);
    await runInDurableObject(room, (_, state) => {
      const body = state.storage.sql.exec<{ body: string }>("SELECT body FROM note").one().body;
      for (let seq = 2; seq <= 150; seq++) {
        state.storage.sql.exec("INSERT INTO note (seq, body) VALUES (?, ?)", seq, body);
      }
    });
    expect(await room.notes(0, -1)).toEqual([]);
    expect(await room.notes(0, 0)).toEqual([]);
    expect(await room.notes(0, 1_000_000)).toHaveLength(100);
  });
});

describe("PairRoom close handling", () => {
  it("answers a close that carries no code", async () => {
    const room = await openRoom();
    const { webSocket } = await connect(room, upgrade(alice));
    webSocket?.accept();
    const closed = new Promise<number>((resolve) => {
      webSocket?.addEventListener("close", (event) => {
        resolve(event.code);
      });
    });

    webSocket?.close();

    expect(await closed).toBe(1000);
  });

  it.each([0, 999, 1004, 5000, 65535])("does not throw on the invalid code %i", async (code) => {
    const room = await openRoom();
    const { webSocket } = await connect(room, upgrade(alice));
    webSocket?.accept();
    const closed = new Promise<number>((resolve) => {
      webSocket?.addEventListener("close", (event) => {
        resolve(event.code);
      });
    });

    await runInDurableObject(room, (instance, state) => {
      const [socket] = state.getWebSockets(alice);
      if (socket === undefined) throw new Error("expected an accepted socket");
      expect(() => {
        instance.webSocketClose(socket, code);
      }).not.toThrow();
    });

    expect(await closed).toBe(1002);
  });
});
