import { env } from "cloudflare:workers";
import { evictDurableObject, runInDurableObject } from "cloudflare:test";
import { Schema } from "effect";
import { describe, expect, it, vi } from "vitest";
import { IdempotencyKey, MediaKey, UserId } from "@billet/contracts-domain/ids";
import { freeInk, InkId } from "@billet/contracts-domain/inks";
import { PairId } from "@billet/contracts-domain/pair-id";
import { CollectionId, RoomItemId } from "@billet/contracts-domain/shop";
import { NatureSeed } from "@billet/contracts-domain/cat";
import { RecordCatEventRequest, SaveCatRequest } from "@billet/contracts-http-api/cat";
import { ChangeListRequest } from "@billet/contracts-http-api/lists";
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
const tower = Schema.decodeUnknownSync(RoomItemId)("tower");
const yarn = Schema.decodeUnknownSync(RoomItemId)("yarn");
const corner = Schema.decodeUnknownSync(CollectionId)("mochis-corner");
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
      streak: { days: 4, best: 0 },
      inks: [],
      items: [],
      wishlist: [],
      layout: [],
      stowed: [],
      layoutLog: [],
      bonuses: [],
      moods: [],
      welcomed: true,
      // The welcome coins, and the note's 10.
      wallet: { balance: 570, day: expect.anything(), care: 0, notes: 10, games: 0, lists: 0 },
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
      expect.stringContaining("_shop"),
      expect.stringContaining("_shop_rewards"),
      expect.stringContaining("_gifts"),
      expect.stringContaining("_gift_occasion"),
      expect.stringContaining("_mood"),
      expect.stringContaining("_lists"),
      expect.stringContaining("_list_media"),
      expect.stringContaining("_list_travel"),
      expect.stringContaining("_movie_swipes"),
      expect.stringContaining("_guess"),
      expect.stringContaining("_riddles"),
      expect.stringContaining("_streak"),
      expect.stringContaining("_layout"),
      expect.stringContaining("_stowed_piece"),
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

  it("gives a room stored before the welcome coins them once, keeping its balance", async () => {
    const room = await openRoom();
    // A room as the build before the welcome coins left it: 30 coins and no entry.
    await runInDurableObject(room, (_, state) => {
      state.storage.sql.exec("UPDATE room SET welcomed = 0");
      state.storage.sql.exec("UPDATE wallet SET balance = 30");
      state.storage.sql.exec("DELETE FROM coin_entry");
    });
    await evictDurableObject(room);

    expect(await room.coins(undefined, 10)).toMatchObject({ balance: 590 });
    await room.setPresence(alice, "drawing");
    await evictDurableObject(room);
    const coins = await room.coins(undefined, 10);
    expect(coins?.balance).toBe(590);
    expect(coins?.entries.map((entry) => entry.id)).toEqual(["gift:welcome"]);
    expect(await room.snapshot()).toMatchObject({ welcomed: true });
  });

  it("keeps the gift day and the bonuses across eviction", async () => {
    const room = await openRoom();
    // Every piece of Mochi's corner but the tower, and the coins for it.
    await runInDurableObject(room, (_, state) => {
      state.storage.sql.exec("UPDATE wallet SET balance = 1000");
      for (const [position, item] of ["yarn", "mouse", "donutbed"].entries()) {
        state.storage.sql.exec(
          "INSERT INTO owned_item (item_id, position) VALUES (?, ?)",
          item,
          position,
        );
      }
    });
    await evictDurableObject(room);
    expect(await room.order(alice, newKey(), { _tag: "Item", item: tower }, 0)).toMatchObject({
      _tag: "Accepted",
    });
    expect(await room.claimBonus(bob, corner)).toMatchObject({ _tag: "Accepted" });
    expect(await room.openGift(bob, 0)).toMatchObject({ _tag: "Accepted" });
    await evictDurableObject(room);
    const shop = await room.shop();
    expect(shop).toMatchObject({ bonuses: [corner] });
    expect(shop).toHaveProperty("giftDay");
    expect(await room.claimBonus(alice, corner)).toMatchObject({
      outputs: [{ _tag: "CoinsRepeated", entry: { id: "bonus:mochis-corner" } }],
    });
  });

  it("keeps the pair's pieces and wishlist across eviction", async () => {
    const room = await openRoom();
    await runInDurableObject(room, (_, state) => {
      state.storage.sql.exec(
        "INSERT OR REPLACE INTO wallet (id, balance, care, notes, games) VALUES (1, 1000, 0, 0, 0)",
      );
    });
    await room.setWish(alice, tower, true);
    await room.setWish(bob, yarn, true);
    expect(await room.order(bob, newKey(), { _tag: "Item", item: tower })).toMatchObject({
      _tag: "Accepted",
    });
    await evictDurableObject(room);
    expect(await room.shop()).toEqual({
      balance: 460,
      inks: [freeInk],
      items: ["lamp", "rug", tower],
      wishlist: [yarn],
      bonuses: [],
      layout: [],
      stowed: [],
    });
  });

  it("keeps gift wishes and plans across eviction, and the plan only in the giver's view", async () => {
    const room = await openRoom();
    const wish = newKey();
    await room.gifts(alice, {
      _tag: "SaveWish",
      wish: { id: wish, title: "Bracelet", link: "", price: "$65", note: "", mostWanted: true },
    });
    await room.gifts(bob, { _tag: "SetPlan", wish, stage: "planning" });
    await evictDurableObject(room);

    expect(await room.gifts(alice, { _tag: "View" })).toMatchObject({
      _tag: "Done",
      view: { wishes: [{ id: wish, owner: alice }], plans: [], surprise: true },
    });
    expect(await room.gifts(bob, { _tag: "View" })).toMatchObject({
      _tag: "Done",
      view: { plans: [{ wish, stage: "planning" }], surprise: false },
    });
    expect(await room.gifts(mallory, { _tag: "View" })).toEqual({
      _tag: "Refused",
      reason: "NotOpen",
    });
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

  it("closes every open socket when the pair ends, and again harmlessly", async () => {
    const room = await openRoom();
    const sockets = await Promise.all([alice, bob].map((user) => connect(room, upgrade(user))));
    const closed = sockets.map(
      ({ webSocket }) =>
        new Promise<string>((resolve) => {
          webSocket?.addEventListener("close", (event) => {
            resolve(`${event.code} ${event.reason}`);
          });
          webSocket?.accept();
        }),
    );

    await room.endSessions();
    await room.endSessions();

    expect(await Promise.all(closed)).toEqual(["1000 pair ended", "1000 pair ended"]);
  });
});

describe("PairRoom destroy", () => {
  it("closes the sockets and deletes the notes, and again harmlessly", async () => {
    const room = await openRoom();
    await room.sendNote(alice, photo());
    const { webSocket } = await connect(room, upgrade(alice));
    const closed = new Promise<string>((resolve) => {
      webSocket?.addEventListener("close", (event) => {
        resolve(`${event.code} ${event.reason}`);
      });
      webSocket?.accept();
    });

    await room.destroy();
    await room.destroy();
    expect(await closed).toBe("1000 pair ended");

    expect(await room.notes(0, 10)).toEqual([]);
    expect(await room.snapshot()).toEqual({ _tag: "Vacant" });
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

  it("keeps lists in SQLite across eviction, pushes changes to sockets that follow them, pays a tick once and forgets them with the pair", async () => {
    const room = await openRoom();
    const follower = await open(room, bob);
    const notesOnly = await open(room, alice);
    follower.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, lists: true }));
    notesOnly.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    await until(() => follower.frames.some((f) => f._tag === "ListsChanged"));

    const list = "00000000-0000-4000-8000-00000000f001";
    const item = "00000000-0000-4000-8000-00000000f002";
    const change = (body: unknown) =>
      Schema.decodeUnknownSync(ChangeListRequest)({ change: body, utcOffsetSeconds: 0 });
    const dune = {
      kind: "movie",
      tmdb: 438631,
      year: 2021,
      posterPath: "/d5NXSklXo0qyIYkgV94XAgMIckC.jpg",
    };
    const create = change({
      _tag: "CreateList",
      key: newKey(),
      list,
      kind: "watch",
      title: "To watch",
      icon: { symbol: "film", tint: "lilac" },
    });
    expect(await room.lists(alice, create)).toMatchObject({ _tag: "Done" });
    expect(
      await room.lists(
        alice,
        change({ _tag: "AddItem", key: newKey(), list, item, text: "Dune", media: dune }),
      ),
    ).toMatchObject({ _tag: "Done" });
    await until(() =>
      follower.frames.some(
        (f) => f._tag === "ListsChanged" && JSON.stringify(f["lists"]).includes("Dune"),
      ),
    );

    await evictDurableObject(room);

    const tick = change({ _tag: "TickItem", key: newKey(), list, item });
    expect(await room.lists(bob, tick)).toMatchObject({
      _tag: "Done",
      lists: [{ id: list, items: [{ text: "Dune", author: alice, doneBy: bob, media: dune }] }],
    });
    expect(await room.lists(bob, tick)).toMatchObject({ _tag: "Done" });
    const been = {
      country: "JP",
      place: true,
      visitedIn: "2026-10",
      moments: ["00000000-0000-4000-8000-00000000f0d1"],
    };
    expect(
      await room.lists(
        bob,
        change({ _tag: "EditItem", key: newKey(), list, item, text: "Kyoto", ...been }),
      ),
    ).toMatchObject({ _tag: "Done" });
    await evictDurableObject(room);
    expect(await room.lists(bob)).toMatchObject({
      _tag: "Done",
      lists: [{ id: list, items: [{ text: "Kyoto", ...been }] }],
    });
    expect(
      await room.lists(bob, change({ _tag: "UntickItem", key: newKey(), list, item })),
    ).toMatchObject({ _tag: "Done" });
    expect(
      await room.lists(alice, change({ _tag: "TickItem", key: newKey(), list, item })),
    ).toMatchObject({ _tag: "Done" });
    const coins = await room.coins(undefined, 10);
    expect(coins?.entries.filter((entry) => entry.id === `earn:list:${item}`)).toHaveLength(1);
    expect(notesOnly.frames.some((f) => f._tag === "ListsChanged")).toBe(false);
    expect(await room.lists(mallory)).toEqual({ _tag: "Refused", reason: "NotOpen" });
    expect(
      await room.lists(
        alice,
        change({
          _tag: "AddItem",
          key: newKey(),
          list: "00000000-0000-4000-8000-00000000f0ff",
          item,
          text: "Gone",
        }),
      ),
    ).toEqual({ _tag: "Refused", reason: "ListNotFound" });

    await room.forgetMember(alice);
    expect(await room.lists(bob)).toEqual({ _tag: "Done", lists: [] });
  });

  it("keeps Pick tonight swipes in SQLite, sends a match to both partners once, and forgets them with the pair", async () => {
    const room = await openRoom();
    const follower = await open(room, alice);
    const notesOnly = await open(room, bob);
    follower.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, lists: true }));
    notesOnly.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    await until(() => follower.frames.some((f) => f._tag === "ListsChanged"));

    const arrival = { _tag: "Title", kind: "movie", tmdb: 329865 } as const;
    const swipe = (choice: "pass" | "seen" | "want") =>
      ({ _tag: "Swipe", title: arrival, choice, name: "Arrival" }) as const;
    expect(await room.pickTonight(alice, swipe("want"))).toMatchObject({
      _tag: "Done",
      view: { swipes: [{ title: arrival, choice: "want" }], partnerPicked: 0, matches: [] },
    });

    await evictDurableObject(room);

    const matched = await room.pickTonight(bob, swipe("want"));
    expect(matched).toMatchObject({
      _tag: "Done",
      view: { partnerPicked: 1, match: { title: arrival, name: "Arrival" } },
    });
    await until(() => follower.frames.some((f) => f._tag === "MatchFound"));
    const again = await room.pickTonight(bob, swipe("want"));
    expect(again._tag === "Done" && again.view.match).toBeUndefined();
    expect(again._tag === "Done" && again.view.matches).toHaveLength(1);
    expect(follower.frames.filter((f) => f._tag === "MatchFound")).toHaveLength(1);
    expect(notesOnly.frames.some((f) => f._tag === "MatchFound")).toBe(false);
    expect(await room.pickTonight(mallory, { _tag: "View" })).toEqual({
      _tag: "Refused",
      reason: "NotOpen",
    });

    await room.forgetMember(alice);
    expect(await room.pickTonight(bob, { _tag: "View" })).toMatchObject({
      _tag: "Done",
      view: { swipes: [], partnerPicked: 0, matches: [] },
    });
  });

  it("keeps a Who knows who round in SQLite, counts answers to the partner, reveals to both, and forgets it with the pair", async () => {
    const room = await openRoom();
    const a = await open(room, alice);
    const b = await open(room, bob);
    const notesOnly = await open(room, bob);
    a.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, guess: true, shop: true }));
    b.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, guess: true }));
    notesOnly.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    await until(() => a.frames.some((f) => f._tag === "ShopChanged"));

    const first = await room.guess(alice, { _tag: "View" });
    if (first._tag !== "Done") throw new Error(first.reason);
    const { round } = first.view;
    expect(round.questions).toHaveLength(5);
    const answer = (by: typeof alice, question: number, option: number) =>
      room.guess(by, { _tag: "Answer", round: round.id, question, option } as never);

    await answer(alice, round.questions[0]!, 1);
    await until(() => b.frames.some((f) => f._tag === "GuessProgress"));
    expect(b.frames.find((f) => f._tag === "GuessProgress")).toEqual({
      _tag: "GuessProgress",
      round: round.id,
      answered: 1,
    });
    expect(a.frames.some((f) => f._tag === "GuessProgress")).toBe(false);
    expect(await answer(alice, round.questions[0]!, 2)).toEqual({
      _tag: "Refused",
      reason: "Answered",
    });

    await evictDurableObject(room);

    for (const question of round.questions.slice(1)) await answer(alice, question, 1);
    const hidden = await room.guess(bob, { _tag: "View" });
    expect(hidden).toMatchObject({ _tag: "Done", view: { answers: [], partnerAnswered: 5 } });
    expect(hidden._tag === "Done" && hidden.view.reveal).toBeUndefined();

    for (const question of round.questions) await answer(bob, question, 1);
    await until(() => a.frames.some((f) => f._tag === "GuessRevealed"));
    await until(() => b.frames.some((f) => f._tag === "GuessRevealed"));
    const revealed = a.frames.find((f) => f._tag === "GuessRevealed");
    expect(revealed).toMatchObject({ round: round.id, reveal: expect.any(Array) });
    const reveal = (revealed?.reveal ?? []) as ReadonlyArray<{ hit: boolean }>;
    expect(reveal.map((q) => q.hit)).toEqual([true, true, true, true, true]);
    const guesserIsAlice = round.subject === bob;
    expect(revealed?.score).toMatchObject({
      week: guesserIsAlice ? { mine: 5, partner: 0 } : { mine: 0, partner: 5 },
    });
    await until(() => a.frames.filter((f) => f._tag === "ShopChanged").length > 1);
    const coins = await room.coins(undefined, 100);
    expect(coins?.entries.map((entry) => entry.id)).toEqual(
      expect.arrayContaining([
        `earn:round:${round.id}`,
        `earn:guess:${round.id}.${round.questions[0]}`,
      ]),
    );
    expect(notesOnly.frames.some((f) => f._tag.startsWith("Guess"))).toBe(false);
    expect(await room.guess(mallory, { _tag: "View" })).toEqual({
      _tag: "Refused",
      reason: "NotOpen",
    });

    await room.forgetMember(alice);
    const after = await room.guess(bob, { _tag: "View" });
    expect(after).toMatchObject({
      _tag: "Done",
      view: { answers: [], partnerAnswered: 0, score: { allTime: { mine: 0, partner: 0 } } },
    });
  });

  it("sends a socket that resumes following Who knows who the partner's progress, then the reveal", async () => {
    const room = await openRoom();
    const first = await room.guess(alice, { _tag: "View" });
    if (first._tag !== "Done") throw new Error(first.reason);
    const { round } = first.view;
    const answer = (by: typeof alice, question: number) =>
      room.guess(by, { _tag: "Answer", round: round.id, question, option: 1 } as never);

    for (const question of round.questions.slice(0, 2)) await answer(alice, question);
    const late = await open(room, bob);
    late.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, guess: true }));
    await until(() => late.frames.some((f) => f._tag === "GuessProgress"));
    expect(late.frames.find((f) => f._tag === "GuessProgress")).toEqual({
      _tag: "GuessProgress",
      round: round.id,
      answered: 2,
    });

    for (const question of round.questions.slice(2)) await answer(alice, question);
    for (const question of round.questions) await answer(bob, question);
    const after = await open(room, alice);
    after.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, guess: true }));
    await until(() => after.frames.some((f) => f._tag === "GuessRevealed"));
    expect(after.frames.find((f) => f._tag === "GuessRevealed")).toMatchObject({
      round: round.id,
      reveal: expect.any(Array),
    });
    expect(after.frames.some((f) => f._tag === "GuessProgress")).toBe(false);
  });

  it("sends the reveal again for a repeated last answer of a revealed round", async () => {
    const room = await openRoom();
    const first = await room.guess(alice, { _tag: "View" });
    if (first._tag !== "Done") throw new Error(first.reason);
    const { round } = first.view;
    const answer = (by: typeof alice, question: number) =>
      room.guess(by, { _tag: "Answer", round: round.id, question, option: 0 } as never);
    for (const question of round.questions) await answer(alice, question);
    const a = await open(room, alice);
    a.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, guess: true }));
    await until(() => a.frames.some((f) => f._tag === "Presence"));
    for (const question of round.questions) await answer(bob, question);
    const reveals = () => a.frames.filter((f) => f._tag === "GuessRevealed").length;
    await until(() => reveals() === 1);
    await answer(bob, round.questions.at(-1)!);
    await until(() => reveals() === 2);
  });

  it("keeps draw-guess riddles in SQLite, hides the word from the guesser, pays the end and forgets them with the pair", async () => {
    const room = await openRoom();
    const a = await open(room, alice);
    const b = await open(room, bob);
    const notesOnly = await open(room, bob);
    a.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, riddle: true, shop: true }));
    b.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, riddle: true }));
    notesOnly.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    await until(() => a.frames.some((f) => f._tag === "ShopChanged"));

    const id = (n: number) => `00000000-0000-4000-8000-00000000900${n}`;
    const sendRiddle = (n: number, word: string) =>
      room.riddle(alice, {
        _tag: "Send",
        id: id(n),
        word,
        compact: { version: 1, strokes: [] },
        image: "pairs/pair/riddles/r.png",
      } as never);
    expect(await sendRiddle(1, "Cat")).toMatchObject({ _tag: "Changed", riddle: { word: "cat" } });
    await until(() => b.frames.some((f) => f._tag === "RiddleChanged"));
    await until(() => a.frames.some((f) => f._tag === "RiddleChanged"));
    const seen = (frames: typeof a.frames) =>
      frames.find((f) => f._tag === "RiddleChanged")?.["riddle"] as { word?: string };
    expect(seen(a.frames).word).toBe("cat");
    expect(seen(b.frames).word).toBeUndefined();
    expect(JSON.stringify(b.frames)).not.toContain('"cat"');

    await evictDurableObject(room);

    const late = await open(room, bob);
    late.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, riddle: true }));
    await until(() => late.frames.some((f) => f._tag === "RiddleChanged"));
    expect(seen(late.frames)).toMatchObject({ id: id(1), shape: [3] });
    expect(seen(late.frames).word).toBeUndefined();

    const key = "00000000-0000-4000-8000-000000000077";
    const guess = (text: string) =>
      room.riddle(bob, { _tag: "Guess", riddle: id(1), key, guess: text } as never);
    expect(await guess("CAT")).toMatchObject({ _tag: "Changed", right: true });
    expect(await guess("dog")).toMatchObject({
      _tag: "Changed",
      right: true,
      riddle: { tries: 1 },
    });
    await until(() => a.frames.filter((f) => f._tag === "ShopChanged").length > 1);
    const coins = await room.coins(undefined, 100);
    expect(coins?.entries.find((entry) => entry.id === `earn:${id(1)}`)?.amount).toBe(10);
    expect(notesOnly.frames.some((f) => f._tag === "RiddleChanged")).toBe(false);
    expect(await room.riddle(mallory, { _tag: "View" })).toEqual({
      _tag: "Refused",
      reason: "NotOpen",
    });

    await room.forgetMember(alice);
    expect(await room.riddle(bob, { _tag: "View" })).toEqual({
      _tag: "Listed",
      view: { open: [], ended: [], series: 0, best: 0 },
    });
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

  it("keeps each member's latest check-in in SQLite, tells every socket that follows moods, and forgets them with the pair", async () => {
    const room = await openRoom();
    const partner = await open(room, alice);
    const ownOther = await open(room, bob);
    const older = await open(room, alice);
    partner.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, moods: true }));
    ownOther.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, moods: true }));
    older.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    // A socket that has seen the note has had its Resume read, so it follows moods from here.
    await room.sendNote(alice, photo());
    await until(() => partner.frames.some((f) => f._tag === "NoteReceived"));
    await until(() => ownOther.frames.some((f) => f._tag === "NoteReceived"));

    expect(await room.setMood(bob, { mood: "busy", note: "  till six " })).toMatchObject({
      _tag: "Accepted",
      outputs: [{ _tag: "MoodSet", checkIn: { user: bob, mood: "busy", note: "till six" } }],
    });
    expect(await room.setMood(alice, { mood: "missing" })).toMatchObject({ _tag: "Accepted" });
    expect(await room.setMood(mallory, { mood: "happy" })).toMatchObject({
      _tag: "Rejected",
      rejection: { _tag: "NotAMember" },
    });
    await evictDurableObject(room);
    expect(await room.setMood(bob, { mood: "sleepy" })).toMatchObject({ _tag: "Accepted" });

    const moodsOf = (frames: ReadonlyArray<{ _tag: string; [key: string]: unknown }>) =>
      frames.filter((f) => f._tag === "MoodChanged").map((f) => f["checkIn"]);
    await until(() => moodsOf(partner.frames).length === 3);
    await until(() => moodsOf(ownOther.frames).length === 3);
    expect(moodsOf(partner.frames)).toEqual([
      expect.objectContaining({ user: bob, mood: "busy", note: "till six" }),
      expect.objectContaining({ user: alice, mood: "missing" }),
      expect.not.objectContaining({ note: expect.anything() }),
    ]);
    expect(moodsOf(older.frames)).toEqual([]);

    await evictDurableObject(room);
    expect(await room.moods()).toEqual([
      expect.objectContaining({ user: alice, mood: "missing" }),
      expect.objectContaining({ user: bob, mood: "sleepy" }),
    ]);
    expect(await room.snapshot()).toMatchObject({
      _tag: "Active",
      moods: [{ user: alice }, { user: bob }],
    });
    const inbox = await room.activity(alice, undefined, 10);
    expect(inbox.items.filter((i) => i.event._tag === "MoodShared")).toEqual([
      expect.objectContaining({ actor: "Partner", event: { _tag: "MoodShared", mood: "sleepy" } }),
      expect.objectContaining({ actor: "Me", event: { _tag: "MoodShared", mood: "missing" } }),
    ]);

    const late = await open(room, alice);
    late.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 1, moods: true }));
    await until(() => moodsOf(late.frames).length === 2);
    expect(moodsOf(late.frames)).toEqual([
      expect.objectContaining({ user: alice, mood: "missing" }),
      expect.objectContaining({ user: bob, mood: "sleepy" }),
    ]);

    await room.forgetMember(alice);
    expect(await room.moods()).toEqual([]);
  });

  it("sends the pair's streak to sockets that follow it, on the resume and after each counted day", async () => {
    const room = await openRoom();
    const partner = await open(room, alice);
    const ownOther = await open(room, bob);
    const older = await open(room, alice);
    partner.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, streak: true }));
    ownOther.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, streak: true }));
    older.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    const streaksOf = (frames: ReadonlyArray<{ _tag: string; [key: string]: unknown }>) =>
      frames.filter((f) => f._tag === "StreakChanged").map((f) => f["streak"]);
    await until(() => streaksOf(partner.frames).length === 1);
    await until(() => streaksOf(ownOther.frames).length === 1);
    expect(streaksOf(partner.frames)).toEqual([{ days: 0, best: 0 }]);
    // A socket that has seen the note has had its Resume read.
    await room.sendNote(alice, photo());
    await until(() => older.frames.some((f) => f._tag === "NoteReceived"));

    const today = { at: 1_700_000_000_000, utcOffsetSeconds: 0 };
    expect(await room.recordStreakDay(bob, today)).toMatchObject({ _tag: "Accepted" });
    // The same day again, and a restore the room refuses, change nothing and send nothing.
    expect(await room.recordStreakDay(alice, today)).toMatchObject({
      _tag: "Accepted",
      outputs: [],
    });
    expect(await room.restoreStreak(alice, { utcOffsetSeconds: 0 })).toMatchObject({
      _tag: "Rejected",
      rejection: { _tag: "StreakNotRestorable" },
    });
    await until(() => streaksOf(partner.frames).length === 2);
    await until(() => streaksOf(ownOther.frames).length === 2);
    expect(streaksOf(partner.frames)[1]).toEqual(expect.objectContaining({ days: 1, best: 1 }));
    await room.sendNote(alice, photo());
    await until(() => partner.frames.filter((f) => f._tag === "NoteReceived").length === 2);
    expect(streaksOf(partner.frames)).toHaveLength(2);
    expect(streaksOf(older.frames)).toEqual([]);

    await evictDurableObject(room);
    const late = await open(room, alice);
    late.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 2, streak: true }));
    await until(() => streaksOf(late.frames).length === 1);
    expect(streaksOf(late.frames)).toEqual([expect.objectContaining({ days: 1 })]);
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

  it("sends the pair's shop to sockets that follow it, on resume and on every change", async () => {
    const room = await openRoom();
    const bobShop = await open(room, bob);
    const bobOld = await open(room, bob);
    const aliceShop = await open(room, alice);
    bobShop.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, shop: true }));
    bobOld.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0 }));
    aliceShop.socket.send(JSON.stringify({ _tag: "Resume", lastSeq: 0, shop: true }));
    const shopsOf = (frames: ReadonlyArray<{ _tag: string; [key: string]: unknown }>) =>
      frames.filter((f) => f._tag === "ShopChanged").map((f) => f["shop"]);
    await until(
      () => shopsOf(bobShop.frames).length === 1 && shopsOf(aliceShop.frames).length === 1,
    );
    const start = await room.shop();
    expect(shopsOf(bobShop.frames)).toEqual([start]);

    // A note earns, so it changes the shop; a presence does not.
    await room.sendNote(alice, photo());
    const earned = await room.shop();
    await room.setPresence(alice, "drawing");
    await room.setWish(bob, tower, true);
    await until(() => shopsOf(aliceShop.frames).length === 3);
    expect(earned?.balance).toBeGreaterThan(start?.balance ?? 0);
    expect(shopsOf(aliceShop.frames).slice(1)).toEqual([earned, { ...earned, wishlist: [tower] }]);
    expect(shopsOf(bobShop.frames)).toHaveLength(3);
    expect(shopsOf(bobOld.frames)).toEqual([]);
  });

  it("tells the partner the user is away when their last socket drops, and stores a drawing as stopped", async () => {
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
    await until(() => b.frames.some((f) => f._tag === "Presence" && f["state"] === "away"));
    expect(await room.snapshot()).toMatchObject({
      members: [{ user: alice, presence: "idle" }, { user: bob }],
    });
  });

  const presences = (frames: Array<{ _tag: string; [key: string]: unknown }>) =>
    frames.filter((f) => f._tag === "Presence").map((f) => f["state"]);

  it("says the partner is away on connect while they have no socket", async () => {
    const room = await openRoom();
    const a = await open(room, alice);
    await until(() => presences(a.frames).length === 1);
    expect(presences(a.frames)).toEqual(["away"]);
  });

  it("tells the partner the user arrived on their first socket only", async () => {
    const room = await openRoom();
    const a = await open(room, alice);
    await until(() => presences(a.frames).length === 1);
    const b = await open(room, bob);
    await until(() => presences(a.frames).length === 2 && presences(b.frames).length === 1);
    expect(presences(a.frames)).toEqual(["away", "idle"]);
    expect(presences(b.frames)).toEqual(["idle"]);

    // A second socket of Bob's, the canvas say: Alice already knows he is here.
    const second = await open(room, bob);
    await until(() => presences(second.frames).length === 1);
    second.socket.close(1000);
    b.socket.send(JSON.stringify({ _tag: "Presence", state: "idle" }));
    await until(() => presences(a.frames).length === 3);
    expect(presences(a.frames)).toEqual(["away", "idle", "idle"]);

    b.socket.close(1000);
    await until(() => presences(a.frames).length === 4);
    expect(presences(a.frames).at(-1)).toBe("away");
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
    expect(live(b.frames)[2]).toEqual({
      _tag: "StrokePoints",
      id: 1,
      points: [{ x: 3, y: 4 }],
      relayedAt: expect.any(Number),
    });
    // Stamped with when each frame reached the room, so the partner can pace a clump.
    const stamps = live(b.frames)
      .filter((f) => f._tag === "StrokePoints")
      .flatMap((f) => ("relayedAt" in f && typeof f.relayedAt === "number" ? [f.relayedAt] : []));
    expect(stamps[1]).toBeGreaterThanOrEqual(stamps[0] ?? Infinity);
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
