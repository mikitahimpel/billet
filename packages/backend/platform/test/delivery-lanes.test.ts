import { env } from "cloudflare:workers";
import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { Schema } from "effect";
import { describe, expect, it, vi } from "vitest";
import { maxAttempts } from "@billet/backend-pair-room/delivery-ledger";
import { IdempotencyKey, MediaKey, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import type { PairRoom } from "../src/pair-room-durable-object.ts";
import { testNowOf } from "./test-now.ts";

const alice = Schema.decodeUnknownSync(UserId)("user-alice");
const bob = Schema.decodeUnknownSync(UserId)("user-bob");
const pairId = Schema.decodeUnknownSync(PairId)("pair-1");
let keyCount = 0;
/** A new key each time, so repeated sends are different notes unless a test reuses a key. */
const newKey = () =>
  Schema.decodeSync(IdempotencyKey)(
    `00000000-0000-4000-8000-${String((keyCount += 1)).padStart(12, "0")}`,
  );
const photo = () =>
  SendNoteRequest.cases.Photo.make({
    key: newKey(),
    image: Schema.decodeUnknownSync(MediaKey)("pairs/pair-1/notes/note-1.png"),
    width: 4032,
    height: 3024,
    preview: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
  });

/** A room whose lane sender follows `script`; "Delivered" once the script runs out. */
const laneRoom = async (script: ReadonlyArray<string> = []) => {
  const room = env.LANE_ROOM.get(env.LANE_ROOM.newUniqueId());
  await room.open(pairId, [alice, bob]);
  await runInDurableObject(room, (_, state) => state.storage.put("laneScript", [...script]));
  return room;
};

const calls = (room: ReturnType<typeof env.LANE_ROOM.get>) =>
  runInDurableObject(
    room,
    async (_, state) => ((await state.storage.get<unknown[]>("laneCalls")) ?? []).length,
  );

/** Moves every pending delivery to "now", as if its wait had passed. */
const letWaitsPass = (room: ReturnType<typeof env.LANE_ROOM.get>) =>
  runInDurableObject(room, (_, state) => {
    state.storage.sql.exec("UPDATE delivery SET next_attempt_at = 0 WHERE status = 'pending'");
  });

const alarmAt = (room: ReturnType<typeof env.LANE_ROOM.get>) =>
  runInDurableObject(room, (_, state) => state.storage.getAlarm());

type Room = ReturnType<typeof env.LANE_ROOM.get>;

/**
 * The room's alarm, run now. The room lives at the fixed `TEST_NOW`, far ahead of the real clock,
 * so its alarms never go off by themselves: each try happens where a test runs it.
 */
const runAlarm = async (room: Room) => {
  expect(await runDurableObjectAlarm(room)).toBe(true);
};

describe("delivery lanes", () => {
  it("hands an accepted note to its lane, and the alarm delivers it once", async () => {
    const room = await laneRoom();
    await room.sendNote(alice, photo());
    await runAlarm(room);
    expect(await room.deliveries()).toMatchObject([{ lane: "AlertPush", status: "delivered" }]);
    expect(await alarmAt(room)).toBeNull();

    await runDurableObjectAlarm(room);
    await runDurableObjectAlarm(room);
    expect(await calls(room)).toBe(1);
  });

  it("hands a new reaction to the lanes under its rev, and a take-back to none", async () => {
    const room = await laneRoom();
    const sent = await room.sendNote(alice, photo());
    if (sent._tag !== "Accepted") throw new Error("note refused");
    const note = sent.outputs.flatMap((o) =>
      o._tag === "NoteAppended" ? [o.entry.note.id] : [],
    )[0]!;
    await room.react(bob, { note, reaction: "wow" });
    await room.react(bob, { note, reaction: "wow" });
    await room.react(bob, { note });
    expect((await room.deliveries()).map((d) => d.noteId).toSorted()).toEqual(
      [note, "reaction:1"].toSorted(),
    );
  });

  it("starts one delivery for a note however often it is handed over", async () => {
    const room = await laneRoom();
    await room.sendNote(alice, photo());
    const [entry] = await room.deliveries();
    await runInDurableObject(room, (instance) => {
      const enqueue = (instance as unknown as { enqueueDeliveries(id: string): Promise<void> })
        .enqueueDeliveries;
      return Promise.all([
        enqueue.call(instance, entry!.noteId),
        enqueue.call(instance, entry!.noteId),
      ]);
    });
    await runAlarm(room);
    expect(await room.deliveries()).toHaveLength(1);
    await runDurableObjectAlarm(room);
    expect(await calls(room)).toBe(1);
  });

  it("enqueues a match again on a repeated ♥ whose first try stored the swipe but no delivery", async () => {
    const room = await laneRoom();
    const want = {
      _tag: "Swipe",
      title: { _tag: "Title", kind: "movie", tmdb: 329865 },
      choice: "want",
      name: "Arrival",
    } as const;
    await room.pickTonight(alice, want);
    await room.pickTonight(bob, want);
    // As if the second swipe failed between storing the swipe and saving its delivery.
    await runInDurableObject(room, (_, state) => {
      state.storage.sql.exec("DELETE FROM delivery");
    });
    expect(await room.pickTonight(bob, want)).toMatchObject({
      _tag: "Done",
      view: { matches: [{}] },
    });
    expect((await room.deliveries()).map((d) => d.noteId)).toEqual([
      expect.stringMatching(/^match:/),
    ]);

    await room.pickTonight(bob, want);
    expect(await room.deliveries()).toHaveLength(1);
  });

  it("enqueues a retried send whose first try stored the note but no delivery", async () => {
    const room = await laneRoom();
    const request = photo();
    await room.sendNote(alice, request);
    // As if the first try failed between storing the note and saving its deliveries.
    await runInDurableObject(room, (_, state) => {
      state.storage.sql.exec("DELETE FROM delivery");
    });
    expect(await room.sendNote(alice, request)).toMatchObject({
      outputs: [{ _tag: "NoteRepeated" }],
    });
    await runAlarm(room);
    expect(await room.deliveries()).toMatchObject([{ lane: "AlertPush", status: "delivered" }]);

    await room.sendNote(alice, request);
    await runDurableObjectAlarm(room);
    expect(await calls(room)).toBe(1);
  });

  it("retries after a failure, with the alarm moved to the wait", async () => {
    const room = await laneRoom(["throw", "Retry"]);
    await room.sendNote(alice, photo());

    await runAlarm(room);
    expect(await room.deliveries()).toMatchObject([{ status: "pending", attempts: 1 }]);
    expect(await alarmAt(room)).toBeGreaterThan(testNowOf(env));

    // Before its wait is over the entry is not due, so firing early does nothing.
    await runDurableObjectAlarm(room);
    expect(await calls(room)).toBe(1);

    await letWaitsPass(room);
    await runDurableObjectAlarm(room);
    expect(await room.deliveries()).toMatchObject([{ status: "pending", attempts: 2 }]);

    await letWaitsPass(room);
    await runDurableObjectAlarm(room);
    expect(await room.deliveries()).toMatchObject([{ status: "delivered", attempts: 2 }]);
    expect(await calls(room)).toBe(3);
    expect(await alarmAt(room)).toBeNull();
  });

  it("abandons after the attempt limit and stops the alarm", async () => {
    const room = await laneRoom(Array.from({ length: maxAttempts }, () => "Retry"));
    await room.sendNote(alice, photo());
    await runAlarm(room);
    for (let i = 1; i < maxAttempts; i++) {
      await letWaitsPass(room);
      await runDurableObjectAlarm(room);
    }
    expect(await room.deliveries()).toMatchObject([{ status: "abandoned", attempts: maxAttempts }]);
    expect(await alarmAt(room)).toBeNull();
    expect(await calls(room)).toBe(maxAttempts);
  });

  it("logs one line per try, and reports the lane's health", async () => {
    const lines: Array<Record<string, unknown>> = [];
    const spy = vi.spyOn(console, "log").mockImplementation((line: string) => {
      lines.push(JSON.parse(line));
    });
    try {
      const room = await laneRoom(["Retry"]);
      await room.sendNote(alice, photo());
      await runAlarm(room);
      await letWaitsPass(room);
      await runDurableObjectAlarm(room);
      expect(await room.deliveryHealth()).toEqual({
        AlertPush: { delivered: 1, abandoned: 0, pending: 0, successRate: 1 },
      });
    } finally {
      spy.mockRestore();
    }
    const tries = lines.filter((line) => line["event"] === "delivery");
    expect(tries).toMatchObject([
      { event: "delivery", lane: "AlertPush", outcome: "Retry", status: "pending", attempts: 1 },
      {
        event: "delivery",
        lane: "AlertPush",
        outcome: "Delivered",
        status: "delivered",
        attempts: 1,
      },
    ]);
  });

  it("abandons at once when the lane says so, for example a dead token", async () => {
    const room = await laneRoom(["Abandon"]);
    await room.sendNote(alice, photo());
    await runAlarm(room);
    expect(await room.deliveries()).toMatchObject([{ status: "abandoned", attempts: 0 }]);
  });

  it("shares the one alarm with a demo bot: the earlier of the two, and both run", async () => {
    const room = await laneRoom();
    await room.startDemo(alice, bob);
    const botWake = await alarmAt(room);
    expect(botWake).toBeGreaterThan(testNowOf(env));

    // Alice's photo is due for delivery now, and for the bot's reaction later.
    await room.sendNote(alice, photo());
    expect(await alarmAt(room)).toBe(testNowOf(env));
    await runAlarm(room);
    expect(await room.deliveries()).toMatchObject([{ status: "delivered" }]);
    const reactAt = await alarmAt(room);
    expect(reactAt).toBeGreaterThan(testNowOf(env));
    expect(reactAt).toBeLessThan(botWake!);

    // At the reaction, the bot reacts and its reaction is handed to the lane on the same alarm.
    await runInDurableObject(room, (instance) =>
      (instance as unknown as { advanceClock(ms: number): void }).advanceClock(
        reactAt! - testNowOf(env),
      ),
    );
    await runAlarm(room);
    expect((await room.reactions(0, 10)).map(({ by }) => by)).toEqual([bob]);
    await runAlarm(room);
    expect((await room.deliveries()).map((entry) => entry.status)).toEqual([
      "delivered",
      "delivered",
    ]);

    await room.stopDemo();
    expect(await alarmAt(room)).toBeNull();
  });

  it("does nothing for a room without lanes", async () => {
    const { PAIR_ROOM } = env as unknown as { PAIR_ROOM: DurableObjectNamespace<PairRoom> };
    const room = PAIR_ROOM.get(PAIR_ROOM.newUniqueId());
    await room.open(pairId, [alice, bob]);
    await room.sendNote(alice, photo());
    expect(await room.deliveries()).toEqual([]);
    expect(await runInDurableObject(room, (_, state) => state.storage.getAlarm())).toBeNull();
  });
});
