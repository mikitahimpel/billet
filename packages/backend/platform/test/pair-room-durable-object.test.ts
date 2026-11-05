import { env } from "cloudflare:workers";
import { evictDurableObject, runInDurableObject } from "cloudflare:test";
import { Schema } from "effect";
import { describe, expect, it, vi } from "vitest";
import { IdempotencyKey, MediaKey, UserId } from "@billet/contracts-domain/ids";
import { freeInk, InkId } from "@billet/contracts-domain/inks";
import { PairId } from "@billet/contracts-domain/pair-id";
import { NatureSeed } from "@billet/contracts-domain/cat";
import { RecordCatEventRequest, SaveCatRequest } from "@billet/contracts-http-api/cat";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { maxFramesPerSecond } from "../src/frame-window.ts";
import { ROOM_USER_HEADER, type PairRoom } from "../src/pair-room-durable-object.ts";
import { testNowOf } from "./test-now.ts";

const { PAIR_ROOM } = env as unknown as { PAIR_ROOM: DurableObjectNamespace<PairRoom> };

const alice = Schema.decodeUnknownSync(UserId)("user-alice");
const bob = Schema.decodeUnknownSync(UserId)("user-bob");
const mallory = Schema.decodeUnknownSync(UserId)("user-mallory");
const pairId = Schema.decodeUnknownSync(PairId)("pair-1");
const image = Schema.decodeUnknownSync(MediaKey)("pairs/pair-1/notes/note-1.png");
let keyCount = 0;
/** A new key each time, so repeated sends are different notes unless a test reuses a key. */
const newKey = () =>
  Schema.decodeSync(IdempotencyKey)(
    `00000000-0000-4000-8000-${String((keyCount += 1)).padStart(12, "0")}`,
  );
const photo = () =>
  SendNoteRequest.cases.Photo.make({
    key: newKey(),
    image,
    width: 4032,
    height: 3024,
    preview: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
  });

const rose = Schema.decodeUnknownSync(InkId)("ink-rose");
const sea = Schema.decodeUnknownSync(InkId)("ink-sea");
const text = (ink: InkId) => SendNoteRequest.cases.Text.make({ key: newKey(), text: "hi", ink });

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
    expect(await room.sendNote(alice, photo())).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "RoomNotOpen" },
    });
  });

  it("opens, and a repeated open changes nothing", async () => {
    const room = await openRoom();
    await room.sendNote(alice, photo());
    await room.open(pairId, [bob, alice]);
    expect(await room.snapshot()).toMatchObject({ _tag: "Active", pairId, lastSeq: 1 });
  });

  it("assigns the id, author and time of a note on the server", async () => {
    const room = await openRoom();
    await room.sendNote(bob, photo());
    const [entry] = await room.notes(0, 10);
    expect(entry).toMatchObject({ seq: 1, note: { _tag: "Photo", author: bob, image } });
    expect(entry?.note.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(entry?.note.sentAt).toBe(testNowOf(env));
  });

  it("round-trips a drawing through SQLite", async () => {
    const room = await openRoom();
    const compact = {
      version: 1,
      strokes: [{ color: "#2A1A1C", width: 3, points: [10, 20, 30, 40] }],
    } as const;
    await room.sendNote(
      alice,
      SendNoteRequest.cases.Drawing.make({ key: newKey(), compact, image }),
    );
    expect((await room.notes(0, 1))[0]?.note).toMatchObject({ _tag: "Drawing", compact });
  });

  it("orders concurrent notes without gaps or duplicates", async () => {
    const room = await openRoom();
    await Promise.all(Array.from({ length: 25 }, () => room.sendNote(alice, photo())));
    const notes = await room.notes(0, 100);
    expect(notes.map((n) => n.seq)).toEqual(Array.from({ length: 25 }, (_, i) => i + 1));
    expect(new Set(notes.map((n) => n.note.id)).size).toBe(25);
    expect(await room.snapshot()).toMatchObject({ lastSeq: 25 });
  });

  it("pages through notes with a cursor and a limit", async () => {
    const room = await openRoom();
    for (let i = 0; i < 3; i += 1) await room.sendNote(alice, photo());
    expect((await room.notes(1, 1)).map((n) => n.seq)).toEqual([2]);
    expect((await room.notes(3, 10)).map((n) => n.seq)).toEqual([]);
  });

  it("rejects a stranger's note and stores nothing", async () => {
    const room = await openRoom();
    expect(await room.sendNote(mallory, photo())).toMatchObject({
      _tag: "Rejected",
      rejection: { _tag: "NotAMember" },
    });
    expect(await room.notes(0, 10)).toEqual([]);
  });

  it("keeps two rooms apart", async () => {
    const [one, two] = [await openRoom(), await openRoom()];
    await one.sendNote(alice, photo());
    expect(await two.snapshot()).toMatchObject({ lastSeq: 0 });
    expect(await two.notes(0, 10)).toEqual([]);
  });
});

describe("PairRoom storage", () => {
  it("keeps notes, presence and the streak across eviction", async () => {
    const room = await openRoom();
    await room.sendNote(alice, photo());
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
      inks: [],
      wallet: { balance: 0, care: 0, notes: 0, games: 0 },
    });
    await room.sendNote(bob, photo());
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
      expect.stringContaining("_delivery"),
      expect.stringContaining("_idempotency_key"),
      expect.stringContaining("_cat"),
      expect.stringContaining("_activity"),
      expect.stringContaining("_owned_ink"),
      expect.stringContaining("_wallet"),
      expect.stringContaining("_reactions"),
    ]);
  });

  it("keeps the pair's inks across eviction, in the order they were granted", async () => {
    const room = await openRoom();
    expect(await room.grantInks([rose])).toMatchObject({
      _tag: "Accepted",
      outputs: [{ _tag: "InksGranted", inks: [rose] }],
    });
    await room.grantInks([sea, rose]);
    await evictDurableObject(room);
    expect(await room.inks()).toEqual([rose, sea]);
    expect(await room.sendNote(bob, text(sea))).toMatchObject({ _tag: "Accepted" });
  });

  it("refuses a text note in an ink the pair has not bought", async () => {
    const room = await openRoom();
    expect(await room.inks()).toEqual([]);
    expect(await room.sendNote(alice, text(rose))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "InkNotOwned", ink: rose },
    });
    expect(await room.sendNote(alice, text(freeInk))).toMatchObject({ _tag: "Accepted" });
    expect(await room.notes(0, 10)).toHaveLength(1);
  });

  it("rolls the state back if appending the note fails", async () => {
    const room = await openRoom();
    await runInDurableObject(room, (_, state) => {
      state.storage.sql.exec("DROP TABLE note");
    });
    const outcome = await runInDurableObject(room, (instance) =>
      instance.sendNote(alice, photo()).then(
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
  const drawing = photo;

  it("skips a note body it cannot decode instead of failing the page", async () => {
    const room = await openRoom();
    await room.sendNote(alice, drawing());
    await room.sendNote(alice, drawing());
    await room.sendNote(bob, drawing());
    await runInDurableObject(room, (_, state) => {
      state.storage.sql.exec("UPDATE note SET body = ? WHERE seq = 2", '{"old":"shape"}');
    });
    const page = await room.notes(0, 10);
    expect(page.map((entry) => entry.seq)).toEqual([1, 3]);
  });

  it("never returns an unbounded page", async () => {
    const room = await openRoom();
    await room.sendNote(alice, drawing());
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

describe("PairRoom realtime across eviction", () => {
  const stroke = { color: "#2A1A1C", width: 3, points: [{ x: 1, y: 2 }] };

  const open = async (room: DurableObjectStub<PairRoom>, user: string) => {
    const { webSocket } = await connect(room, upgrade(user));
    const frames: Array<{ _tag: string; [key: string]: unknown }> = [];
    webSocket?.addEventListener("message", (event) => {
      frames.push(JSON.parse(event.data as string));
    });
    webSocket?.accept();
    return { socket: webSocket!, frames };
  };

  const until = (check: () => boolean) =>
    vi.waitFor(
      () => {
        if (!check()) throw new Error("Never saw the expected frame");
      },
      { timeout: 4000, interval: 5 },
    );

  it("keeps relaying, and keeps each socket's place in the notes, after the object is evicted", async () => {
    const room = await openRoom();
    const a = await open(room, alice);
    const b = await open(room, bob);
    b.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    await room.sendNote(alice, photo());
    await until(() => b.frames.some((f) => f._tag === "NoteReceived"));

    await evictDurableObject(room);

    a.socket.send(JSON.stringify({ _tag: "Stroke", stroke }));
    await until(() => b.frames.some((f) => f._tag === "Stroke"));
    await room.sendNote(alice, photo());
    await until(() => b.frames.filter((f) => f._tag === "NoteReceived").length === 2);
    expect(b.frames.filter((f) => f._tag === "NoteReceived").map((f) => f["seq"])).toEqual([1, 2]);
  });

  it("journals the cat in SQLite, streams each entry to sockets that follow it, and forgets it with the pair", async () => {
    const room = await openRoom();
    const follower = await open(room, bob);
    const notesOnly = await open(room, alice);
    follower.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, lastCatSeq: 0 }));
    notesOnly.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    const seed = Schema.decodeSync(NatureSeed)("42");
    const mochi = Schema.decodeSync(SaveCatRequest)({
      name: "Mochi",
      look: { model: "marmalade", coat: "natural" },
      utcOffsetSeconds: 3600,
    });
    expect((await room.saveCat(alice, mochi, seed))._tag).toBe("Accepted");
    await until(() => follower.frames.some((f) => f._tag === "CatSaved"));

    const pet = Schema.decodeSync(RecordCatEventRequest)({
      id: "00000000-0000-4000-8000-0000000000c1",
      event: { _tag: "Petted" },
    });
    expect((await room.recordCatEvent(bob, pet))._tag).toBe("Accepted");
    await room.sendNote(alice, photo());
    await until(() => follower.frames.filter((f) => f._tag === "CatEntryAdded").length === 2);

    await evictDurableObject(room);
    const view = await room.cat();
    expect(view?.cat).toMatchObject({ name: "Mochi", natureSeed: "42", utcOffsetSeconds: 3600 });
    expect(view?.lastSeq).toBe(2);
    expect(view?.temper.cuddly).toBeGreaterThan(0.5);
    const journal = await room.catJournal(0, 10);
    expect(journal.map((entry) => [entry.seq, entry.by, entry.event._tag])).toEqual([
      [1, bob, "Petted"],
      [2, alice, "NoteShared"],
    ]);
    expect(notesOnly.frames.some((f) => f._tag.startsWith("Cat"))).toBe(false);

    // A repeat answers with the stored entry and sends nothing new.
    const again = await room.recordCatEvent(bob, pet);
    expect(again._tag === "Accepted" && again.outputs.map((o) => o._tag)).toEqual([
      "CatEntryRepeated",
    ]);

    await room.forgetMember(alice);
    expect((await room.cat())?.cat).toBeUndefined();
    expect(await room.catJournal(0, 10)).toEqual([]);
  });

  it("stores reactions in SQLite, streams each change to sockets that follow them, and forgets them with the pair", async () => {
    const room = await openRoom();
    const author = await open(room, alice);
    const older = await open(room, alice);
    author.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, lastReactionRev: 0 }));
    older.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    const sent = await room.sendNote(alice, photo());
    if (sent._tag !== "Accepted") throw new Error("note refused");
    const note = sent.outputs.flatMap((o) =>
      o._tag === "NoteAppended" ? [o.entry.note.id] : [],
    )[0]!;

    expect(await room.react(alice, { note, reaction: "heart" })).toMatchObject({
      _tag: "Rejected",
      rejection: { _tag: "OwnNote" },
    });
    expect((await room.react(bob, { note, reaction: "heart" }))._tag).toBe("Accepted");
    await evictDurableObject(room);
    expect((await room.react(bob, { note, reaction: "fire" }))._tag).toBe("Accepted");
    expect((await room.react(bob, { note }))._tag).toBe("Accepted");
    const changes = () => author.frames.filter((f) => f._tag === "ReactionChanged");
    await until(() => changes().length === 3);
    expect(changes().map((f) => f["reaction"])).toEqual([
      expect.objectContaining({ rev: 1, note, by: bob, reaction: "heart" }),
      expect.objectContaining({ rev: 2, reaction: "fire" }),
      expect.not.objectContaining({ reaction: expect.anything() }),
    ]);
    expect(older.frames.some((f) => f._tag === "ReactionChanged")).toBe(false);

    const late = await open(room, alice);
    late.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 1, lastReactionRev: 1 }));
    await until(() => late.frames.filter((f) => f._tag === "ReactionChanged").length === 1);
    expect(await room.reactions(0, 10)).toEqual([expect.objectContaining({ rev: 3, by: bob })]);
    const inbox = await room.activity(alice, undefined, 10);
    expect(inbox.items.map((i) => [i.actor, i.event._tag])).toContainEqual(["Partner", "Reacted"]);

    await room.forgetMember(alice);
    expect(await room.reactions(0, 10)).toEqual([]);
  });

  it("keeps the Inbox in SQLite, pushes the unread count to sockets that follow it, and forgets it with the pair", async () => {
    const room = await openRoom();
    const bobInbox = await open(room, bob);
    const bobOld = await open(room, bob);
    const aliceInbox = await open(room, alice);
    bobInbox.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, activity: true }));
    bobOld.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    aliceInbox.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, activity: true }));
    const unreadOf = (frames: ReadonlyArray<{ _tag: string; [key: string]: unknown }>) =>
      frames.filter((f) => f._tag === "ActivityUnread").map((f) => f["unread"]);
    await until(() => unreadOf(bobInbox.frames).length === 1);
    expect(unreadOf(bobInbox.frames)).toEqual([0]);

    await room.sendNote(alice, photo());
    await room.sendNote(alice, photo());
    await until(() => unreadOf(bobInbox.frames).length === 3);
    expect(unreadOf(bobInbox.frames)).toEqual([0, 1, 2]);

    await evictDurableObject(room);
    const page = await room.activity(bob, undefined, 1);
    expect(page.items.map((i) => [i.actor, i.event._tag])).toEqual([["Partner", "NoteSent"]]);
    expect(page.unread).toBe(2);
    const rest = await room.activity(bob, page.next, 10);
    expect(rest.items).toHaveLength(1);
    expect(rest.next).toBeUndefined();
    expect((await room.activity(alice, undefined, 10)).unread).toBe(0);

    expect(await room.markActivityRead(bob, page.next!)).toBe(0);
    await until(() => unreadOf(bobInbox.frames).length === 4);
    expect(unreadOf(bobInbox.frames).at(-1)).toBe(0);
    // Alice's count did not move, and an older build never sees the frame.
    expect(unreadOf(aliceInbox.frames)).toEqual([0]);
    expect(unreadOf(bobOld.frames)).toEqual([]);

    await room.forgetMember(alice);
    expect(await room.activity(bob, undefined, 10)).toEqual({ items: [], unread: 0 });
  });

  it("tells the partner the user stopped drawing when their last socket drops", async () => {
    const room = await openRoom();
    const a = await open(room, alice);
    const b = await open(room, bob);
    a.socket.send(JSON.stringify({ _tag: "Presence", state: "drawing" }));
    await until(() => b.frames.some((f) => f._tag === "Presence" && f["state"] === "drawing"));

    // A phone that drops reaches the handler with 1006, the code that returns early.
    await runInDurableObject(room, async (instance, state) => {
      const [socket] = state.getWebSockets(alice);
      if (socket === undefined) throw new Error("expected an accepted socket");
      await instance.webSocketClose(socket, 1006);
    });
    await until(() => b.frames.some((f) => f._tag === "Presence" && f["state"] === "idle"));
    expect(await room.snapshot()).toMatchObject({
      members: [{ user: alice, presence: "idle" }, { user: bob }],
    });
  });

  const live = (frames: Array<{ _tag: string }>) =>
    frames.filter((f) => f._tag.startsWith("Stroke") || f._tag === "Clear");
  const frame = (message: Record<string, unknown>) => JSON.stringify(message);
  const settle = () => new Promise((resolve) => setTimeout(resolve, 150));

  it("relays a live stroke and a clear to the partner only, in order", async () => {
    const room = await openRoom();
    const a = await open(room, alice);
    const b = await open(room, bob);
    a.socket.send(frame({ _tag: "StrokeBegin", id: 1, color: "#7B4FE0", width: 14 }));
    a.socket.send(frame({ _tag: "StrokePoints", id: 1, points: [{ x: 1, y: 2 }] }));
    a.socket.send(frame({ _tag: "StrokePoints", id: 1, points: [{ x: 3, y: 4 }] }));
    a.socket.send(frame({ _tag: "StrokeEnd", id: 1 }));
    a.socket.send(frame({ _tag: "Clear" }));
    await until(() => live(b.frames).length === 5);

    expect(live(b.frames).map((f) => f._tag)).toEqual([
      "StrokeBegin",
      "StrokePoints",
      "StrokePoints",
      "StrokeEnd",
      "Clear",
    ]);
    expect(live(b.frames)[2]).toEqual({ _tag: "StrokePoints", id: 1, points: [{ x: 3, y: 4 }] });
    await settle();
    expect(live(a.frames)).toEqual([]);
  });

  it("drops points of a stroke that was never begun, and batches over the point cap", async () => {
    const room = await openRoom();
    const a = await open(room, alice);
    const b = await open(room, bob);
    const tooMany = Array.from({ length: 65 }, (_, i) => ({ x: i, y: i }));
    a.socket.send(frame({ _tag: "StrokePoints", id: 9, points: [{ x: 1, y: 2 }] }));
    a.socket.send(frame({ _tag: "StrokeBegin", id: 2, color: "#7B4FE0", width: 14 }));
    a.socket.send(frame({ _tag: "StrokePoints", id: 2, points: tooMany }));
    a.socket.send(frame({ _tag: "StrokeEnd", id: 2 }));
    await until(() => live(b.frames).length === 2);
    await settle();

    expect(live(b.frames).map((f) => f._tag)).toEqual(["StrokeBegin", "StrokeEnd"]);
  });

  it("tells the partner to drop the strokes a disconnected phone left open", async () => {
    const room = await openRoom();
    const a = await open(room, alice);
    const b = await open(room, bob);
    a.socket.send(frame({ _tag: "StrokeBegin", id: 4, color: "#7B4FE0", width: 14 }));
    a.socket.send(frame({ _tag: "StrokeBegin", id: 5, color: "#7B4FE0", width: 14 }));
    a.socket.send(frame({ _tag: "StrokeEnd", id: 4 }));
    await until(() => live(b.frames).length === 3);

    // Hibernation must not lose which strokes are open.
    await evictDurableObject(room);
    await runInDurableObject(room, async (instance, state) => {
      const [socket] = state.getWebSockets(alice);
      if (socket === undefined) throw new Error("expected an accepted socket");
      await instance.webSocketClose(socket, 1006);
    });
    await until(() => b.frames.some((f) => f._tag === "StrokeDropped"));
    await settle();

    expect(b.frames.filter((f) => f._tag === "StrokeDropped")).toEqual([
      { _tag: "StrokeDropped", id: 5 },
    ]);
  });

  it("drops the frames past a socket's per-second budget", async () => {
    const room = await openRoom();
    const a = await open(room, alice);
    const b = await open(room, bob);
    a.socket.send(frame({ _tag: "StrokeBegin", id: 1, color: "#7B4FE0", width: 14 }));
    for (let i = 0; i < 99; i += 1) {
      a.socket.send(frame({ _tag: "StrokePoints", id: 1, points: [{ x: i, y: i }] }));
    }
    await until(() => live(b.frames).length >= maxFramesPerSecond);
    await settle();

    // The room lives at the fixed TEST_NOW, so its window never rolls over: exactly the budget.
    expect(live(b.frames)).toHaveLength(maxFramesPerSecond);
  });
});
