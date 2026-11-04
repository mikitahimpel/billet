import { env } from "cloudflare:workers";
import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import {
  EVENING_START,
  MAX_DAILY_DAYS,
  PROMPTS,
  addDays,
  dailyView,
  dueReminders,
  isDay,
  liveDays,
  nextReminderAt,
  offsetOf,
  promptFor,
  recordDaily,
  reminderText,
  seasonOf,
  type DailyDrawing,
  type ReminderInputs,
} from "../src/daily-drawing.ts";
import { parsePlay } from "../src/demo-play.ts";
import type { DemoRoom } from "../src/demo-room-durable-object.ts";
import { routeDemo } from "../src/demo-route.ts";
import type { ClockedDemoRoom } from "./demo-worker.ts";
import { testNowOf } from "./test-now.ts";
import { waitFor } from "./demo-wait.ts";

type Rooms = DurableObjectNamespace<DemoRoom>;
const { DEMO_ROOM, CLOCK_DEMO_ROOM } = env as unknown as {
  DEMO_ROOM: Rooms;
  CLOCK_DEMO_ROOM: DurableObjectNamespace<ClockedDemoRoom>;
};

const alice = "11111111-1111-4111-8111-111111111111";
const bob = "22222222-2222-4222-8222-222222222222";
const uuid = (n: number) => `dddddddd-dddd-4ddd-8ddd-${String(n).padStart(12, "0")}`;

describe("daily prompts", () => {
  it("has at least sixty prompts with unique ids, and some for every season", () => {
    expect(PROMPTS.length).toBeGreaterThanOrEqual(60);
    expect(new Set(PROMPTS.map((p) => p.id)).size).toBe(PROMPTS.length);
    for (const season of ["winter", "spring", "summer", "autumn"] as const) {
      expect(PROMPTS.filter((p) => p.season === season).length).toBeGreaterThanOrEqual(5);
    }
  });

  it("gives a pair the same prompt for a day every time", () => {
    expect(promptFor("PAIRAAAA23", "2026-11-04")).toEqual(promptFor("PAIRAAAA23", "2026-11-04"));
  });

  it("gives different pairs different orders", () => {
    const days = Array.from({ length: 20 }, (_, i) => addDays("2026-10-01", i));
    const a = days.map((d) => promptFor("PAIRAAAA23", d).id);
    const b = days.map((d) => promptFor("PAIRBBBB23", d).id);
    expect(a).not.toEqual(b);
  });

  it("does not repeat a prompt within a season until its set has had its turn", () => {
    // 1 September to 30 November is one autumn of 91 days; the pool is smaller than that.
    const pool = PROMPTS.filter((p) => p.season === undefined || p.season === "autumn").length;
    const days = Array.from({ length: pool }, (_, i) => addDays("2026-09-01", i));
    const ids = days.map((d) => promptFor("PAIRCCCC23", d).id);
    expect(new Set(ids).size).toBe(pool);
  });

  it("only offers a seasonal prompt in its season", () => {
    const seasonal = new Map(PROMPTS.flatMap((p) => (p.season ? [[p.id, p.season]] : [])));
    for (let i = 0; i < 365; i += 1) {
      const day = addDays("2026-01-01", i);
      const season = seasonal.get(promptFor("PAIRDDDD23", day).id);
      if (season !== undefined) expect(season).toBe(seasonOf(day));
    }
  });

  it("covers the three dates a phone may be living", () => {
    expect(liveDays(Date.parse("2026-11-04T12:00:00Z"))).toEqual([
      "2026-11-03",
      "2026-11-04",
      "2026-11-05",
    ]);
    expect(isDay("2026-02-30")).toBe(false);
    expect(isDay("2026-02-28")).toBe(true);
  });
});

describe("daily reveal rule", () => {
  const drawing = (id: string): DailyDrawing => ({ id, ink: `ink-${id}`, at: "2026-11-04T09:00Z" });

  it("hides the partner's drawing until this device has drawn", () => {
    const view = dailyView("PAIR", "2026-11-04", bob, { [alice]: drawing("a") });
    expect(view["mine"]).toBeNull();
    expect(view["theirsDrawn"]).toBe(true);
    expect(view["theirs"]).toBeNull();
  });

  it("shows both once both have drawn", () => {
    const both = { [alice]: drawing("a"), [bob]: drawing("b") };
    const view = dailyView("PAIR", "2026-11-04", bob, both);
    expect(view["mine"]).toEqual(drawing("b"));
    expect(view["theirs"]).toEqual(drawing("a"));
  });

  it("keeps one drawing per device per day, and only the newest days", () => {
    const once = recordDaily({}, alice, "2026-11-04");
    expect(recordDaily(once, alice, "2026-11-04")).toBe(once);
    let days = once;
    for (let i = 1; i <= MAX_DAILY_DAYS + 5; i += 1) {
      days = recordDaily(days, alice, addDays("2026-11-04", i));
    }
    expect(Object.keys(days)).toHaveLength(MAX_DAILY_DAYS);
    expect(days["2026-11-04"]).toBeUndefined();
  });

  it("parses a daily frame and refuses one without ink", () => {
    const frame = { id: uuid(1), kind: "daily", at: "2026-11-04T09:00:00+01:00", ink: "QUJD" };
    expect(parsePlay(frame)).toEqual(frame);
    expect(parsePlay({ ...frame, ink: "" })).toBeUndefined();
    expect(parsePlay({ ...frame, ink: 3 })).toBeUndefined();
  });
});

describe("daily evening reminder", () => {
  // 18:00 UTC on 4 November: 19:00 in Berlin (+60), 13:00 in New York (−300).
  const now = Date.parse("2026-11-04T18:00:00Z");
  const base: ReminderInputs = {
    devices: [alice, bob],
    offsets: { [alice]: 60, [bob]: -300 },
    reminded: {},
    days: {},
  };

  it("reads the offset a time was written in", () => {
    expect(offsetOf("2026-11-04T19:00:00+01:00")).toBe(60);
    expect(offsetOf("2026-11-04T13:00:00-05:00")).toBe(-300);
    expect(offsetOf("2026-11-04T18:00:00Z")).toBe(0);
  });

  it("reminds only a device whose evening it is", () => {
    expect(dueReminders(now, base)).toEqual([
      { device: alice, day: "2026-11-04", partnerDrew: false },
    ]);
  });

  it("says when the partner has drawn", () => {
    const days = { "2026-11-04": [bob] };
    expect(dueReminders(now, { ...base, days })).toEqual([
      { device: alice, day: "2026-11-04", partnerDrew: true },
    ]);
  });

  it("does not remind a device that drew, was reminded, or is unpaired", () => {
    expect(dueReminders(now, { ...base, days: { "2026-11-04": [alice] } })).toEqual([]);
    expect(dueReminders(now, { ...base, reminded: { [alice]: "2026-11-04" } })).toEqual([]);
    expect(dueReminders(now, { ...base, devices: [alice] })).toEqual([]);
  });

  it("never reminds in quiet hours", () => {
    // 22:30 in Berlin.
    expect(dueReminders(Date.parse("2026-11-04T21:30:00Z"), base)).toEqual([]);
  });

  it("schedules the next evening start, skipping a day already done", () => {
    const morning = Date.parse("2026-11-04T08:00:00Z");
    // Berlin's 19:00 is 18:00 UTC; New York's is 00:00 UTC the next day.
    expect(nextReminderAt(morning, base)).toBe(Date.parse("2026-11-04T18:00:00Z"));
    const reminded = { ...base, reminded: { [alice]: "2026-11-04" } };
    expect(nextReminderAt(now, reminded)).toBe(Date.parse("2026-11-05T00:00:00Z"));
    expect(nextReminderAt(now, { ...base, devices: [alice] })).toBeUndefined();
    expect(EVENING_START).toBe(19 * 60);
  });

  it("speaks in the cat's voice", () => {
    const prompt = { id: "x", text: "Our perfect weekend" };
    expect(reminderText("Mochi", prompt, true)).toBe(
      "Mochi is holding a drawing for you. Draw yours to see it 🎨",
    );
    expect(reminderText(undefined, prompt, false)).toBe(
      "The cat wonders what you'll draw today: our perfect weekend ✏️",
    );
  });
});

type Frame = Record<string, unknown>;

interface Peer {
  readonly socket: WebSocket;
  readonly frames: Frame[];
  readonly sendAcked: (frame: Frame) => Promise<void>;
  readonly waitFor: (check: (frames: Frame[]) => boolean, what: string) => Promise<void>;
}

const connect = async (code: string, device: string, rooms: Rooms = DEMO_ROOM): Promise<Peer> => {
  const response = await routeDemo(
    new Request(`https://host/demo/rooms/${code}/socket?device=${device}`, {
      headers: { Upgrade: "websocket" },
    }),
    rooms,
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

const dailyOf = (frames: Frame[], day: string) =>
  frames.filter((f) => f["type"] === "daily" && f["day"] === day).at(-1);

/** The rooms' instant, `TEST_NOW`, moved by `offsetMs`. */
const now = testNowOf(env);
const isoNow = (offsetMs = 0) => new Date(now + offsetMs).toISOString();

describe("daily drawing in the room", () => {
  it("sends the prompts for the live days on connect", async () => {
    const a = await connect("DAYPRM2345", alice);
    const prompts = a.frames.find((f) => f["type"] === "daily-prompts");
    const days = Object.keys((prompts?.["prompts"] ?? {}) as object);
    expect(days).toEqual([...liveDays(now)]);
  });

  it("reveals the partner's drawing only after this device has drawn", async () => {
    const code = "DAYRVA2345";
    const a = await connect(code, alice);
    const b = await connect(code, bob);
    const at = isoNow();
    const day = at.slice(0, 10);

    await a.sendAcked({ type: "play", kind: "daily", id: uuid(10), at, ink: "ALICE" });
    await b.waitFor((f) => dailyOf(f, day)?.["theirsDrawn"] === true, "bob told alice drew");
    expect(dailyOf(b.frames, day)?.["theirs"]).toBeNull();
    expect(JSON.stringify(b.frames)).not.toContain("ALICE");
    expect(dailyOf(a.frames, day)?.["mine"]).toMatchObject({ ink: "ALICE" });

    await b.sendAcked({ type: "play", kind: "daily", id: uuid(11), at, ink: "BOB" });
    await b.waitFor((f) => dailyOf(f, day)?.["theirs"] !== null, "bob sees alice's");
    await a.waitFor((f) => dailyOf(f, day)?.["theirs"] !== null, "alice sees bob's");
    expect(dailyOf(b.frames, day)?.["theirs"]).toMatchObject({ ink: "ALICE" });
    expect(dailyOf(a.frames, day)?.["theirs"]).toMatchObject({ ink: "BOB" });
  });

  it("keeps the first drawing of a day and refuses a far-off time", async () => {
    const code = "DAYNCE2345";
    const a = await connect(code, alice);
    const at = isoNow();
    const day = at.slice(0, 10);
    await a.sendAcked({ type: "play", kind: "daily", id: uuid(20), at, ink: "FIRST" });
    await a.sendAcked({ type: "play", kind: "daily", id: uuid(21), at, ink: "SECOND" });
    expect(dailyOf(a.frames, day)?.["mine"]).toMatchObject({ ink: "FIRST" });

    const old = isoNow(-3 * 86_400_000);
    await a.sendAcked({ type: "play", kind: "daily", id: uuid(22), at: old, ink: "OLD" });
    expect(dailyOf(a.frames, old.slice(0, 10))).toBeUndefined();
  });

  it("replays recent days to a phone that connects, under the same rule", async () => {
    const code = "DAYRPT2345";
    const a = await connect(code, alice);
    const at = isoNow();
    const day = at.slice(0, 10);
    await a.sendAcked({ type: "play", kind: "daily", id: uuid(30), at, ink: "ALICE" });

    const b = await connect(code, bob);
    expect(dailyOf(b.frames, day)).toMatchObject({ mine: null, theirsDrawn: true, theirs: null });
    const again = await connect(code, alice);
    expect(dailyOf(again.frames, day)).toMatchObject({ mine: { ink: "ALICE" } });
  });
});

describe("daily reminder alarm", () => {
  // The room runs on a clock the test sets, but workerd fires a Durable Object's alarm on the real
  // one. A day far in the future keeps every alarm the room schedules in the real future, so only
  // the test runs it. A past day lets the alarm fire by itself, before the test's drawing is in.
  const DAY = "2099-11-04";
  const token = "cd".repeat(32);

  const room = (code: string) => CLOCK_DEMO_ROOM.get(CLOCK_DEMO_ROOM.idFromName(code));

  const calls = (code: string) =>
    runInDurableObject(room(code), (_, state) =>
      state.storage.get<{ body: string }[]>("apnsCalls"),
    );

  it("reminds the one who has not drawn, in their evening, once", async () => {
    const code = "DAYARM2345";
    // 19:30 in Berlin, where both phones write their times.
    const evening = Date.parse(`${DAY}T18:30:00Z`);
    await runInDurableObject(room(code), (instance) => instance.setNow(evening));
    const rooms = CLOCK_DEMO_ROOM as unknown as Rooms;
    const a = await connect(code, alice, rooms);
    const b = await connect(code, bob, rooms);
    b.socket.send(JSON.stringify({ type: "push-token", token }));
    const at = `${DAY}T19:30:00+01:00`;
    await b.sendAcked({ type: "play", kind: "pet", id: uuid(40), at });
    await a.sendAcked({ type: "play", kind: "daily", id: uuid(41), at, ink: "ALICE" });

    expect(await runDurableObjectAlarm(room(code))).toBe(true);
    const sent = (await calls(code)) ?? [];
    expect(sent).toHaveLength(1);
    const body = JSON.parse(sent[0]!.body);
    expect(body.aps.alert.body).toBe(
      "The cat is holding a drawing for you. Draw yours to see it 🎨",
    );
    expect(body.daily).toBe(DAY);

    // The alarm for the next evening may run early in a test; it must not remind twice today.
    await runDurableObjectAlarm(room(code));
    expect((await calls(code)) ?? []).toHaveLength(1);
  });

  it("sends nothing in quiet hours", async () => {
    const code = "DAYQTE2345";
    const late = Date.parse(`${DAY}T21:45:00Z`);
    await runInDurableObject(room(code), (instance) => instance.setNow(late));
    const rooms = CLOCK_DEMO_ROOM as unknown as Rooms;
    const a = await connect(code, alice, rooms);
    const b = await connect(code, bob, rooms);
    b.socket.send(JSON.stringify({ type: "push-token", token }));
    const at = `${DAY}T22:45:00+01:00`;
    await a.sendAcked({ type: "play", kind: "pet", id: uuid(50), at });
    await b.sendAcked({ type: "play", kind: "pet", id: uuid(51), at });
    await runInDurableObject(room(code), (instance) => instance.alarm());
    expect(await calls(code)).toBeUndefined();
  });
});
