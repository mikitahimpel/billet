import { Duration, Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { CatEntry, CatEvent, CatNeeds, type CatTemper } from "@billet/contracts-domain/cat";
import type { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { RecordCatEventRequest, type SaveCatRequest } from "@billet/contracts-http-api/cat";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { catNeeds, lifeConfig } from "../src/cat-life.ts";
import { newTemper, nextTemper, temperHigh, temperLow } from "../src/cat-temper.ts";
import { decide } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import { RoomService } from "../src/room-service.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import {
  active,
  alice,
  bob,
  catProfile,
  image,
  mallory,
  pairId,
  photoFrom,
  uuid,
  withCat,
} from "./samples.ts";

const hour = 3_600_000;
const day = 24 * hour;
/** 2023-11-14 22:13:20 UTC: every clock in these tests starts here. */
const start = 1_700_000_000_000;

const saveCat = (user: UserId, at: number, name = "Mochi") =>
  RoomCommand.cases.SaveCat.make({
    user,
    name: Schema.decodeSync(SaveCatName)(name),
    look: catProfile.look,
    utcOffsetSeconds: catProfile.utcOffsetSeconds,
    natureSeed: catProfile.natureSeed,
    at,
  });
const SaveCatName = RoomCommand.cases.SaveCat.fields.name;

const record = (by: UserId, event: CatEvent, at: number, n = 1) =>
  RoomCommand.cases.RecordCatEvent.make({ id: uuid(n), by, at, event });

describe("decide: the cat", () => {
  it("adopts a cat with its birth and nature, and a later save keeps both", () => {
    const adopted = decide(active, saveCat(alice, start + hour));
    expect(adopted._tag).toBe("Accepted");
    if (adopted._tag !== "Accepted") return;
    expect(adopted.state.cat).toEqual({
      profile: { ...catProfile, bornAt: start + hour },
      temper: newTemper,
      lastSeq: 0,
    });

    const renamed = decide(adopted.state, {
      ...saveCat(bob, start + day, "Pirozhok"),
      natureSeed: Schema.decodeSync(RoomCommand.cases.SaveCat.fields.natureSeed)("7"),
    });
    expect(renamed._tag).toBe("Accepted");
    if (renamed._tag !== "Accepted") return;
    expect(renamed.state.cat?.profile).toEqual({
      ...catProfile,
      bornAt: start + hour,
      name: "Pirozhok",
    });
    expect(renamed.outputs).toEqual([
      { _tag: "CatSaved", cat: renamed.state.cat?.profile, by: bob, adopted: false },
    ]);
  });

  it("refuses a stranger, and care before there is a cat", () => {
    expect(decide(active, saveCat(mallory, start))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "NotAMember", user: mallory },
    });
    expect(decide(active, record(alice, { _tag: "Petted" }, start))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "CatNotAdopted" },
    });
    expect(decide(withCat, record(mallory, { _tag: "Petted" }, start))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "NotAMember", user: mallory },
    });
  });

  it("numbers the journal and moves the temper", () => {
    const first = decide(withCat, record(alice, { _tag: "Petted" }, start + hour, 1));
    if (first._tag !== "Accepted") throw new Error("rejected");
    const second = decide(
      first.state,
      record(bob, { _tag: "Fed", grams: 40 }, start + 2 * hour, 2),
    );
    if (second._tag !== "Accepted") throw new Error("rejected");
    expect(second.outputs.filter((o) => o._tag !== "CoinsEntered")).toEqual([
      {
        _tag: "CatEntryAppended",
        entry: {
          seq: 2,
          id: uuid(2),
          by: bob,
          at: start + 2 * hour,
          event: { _tag: "Fed", grams: 40 },
        },
      },
    ]);
    expect(second.state.cat?.lastSeq).toBe(2);
    expect(second.state.cat?.lastAt).toBe(start + 2 * hour);
    expect(second.state.cat?.temper.cuddly).toBeGreaterThan(newTemper.cuddly);
    expect(second.state.cat?.temper.lazy).toBeGreaterThan(newTemper.lazy);
    expect(second.state.cat?.temper.curious).toBe(newTemper.curious);
  });

  it("journals a note as care when there is a cat, under the note's key", () => {
    const note = photoFrom(bob);
    const key = uuid(9);
    const without = decide(active, RoomCommand.cases.SendNote.make({ note, key }));
    if (without._tag !== "Accepted") throw new Error("rejected");
    expect(without.outputs.map((o) => o._tag)).toEqual(["NoteAppended"]);

    const shared = decide(withCat, RoomCommand.cases.SendNote.make({ note, key }));
    if (shared._tag !== "Accepted") throw new Error("rejected");
    expect(shared.outputs[1]).toEqual({
      _tag: "CatEntryAppended",
      entry: {
        seq: 1,
        id: key,
        by: bob,
        at: note.sentAt,
        event: { _tag: "NoteShared", note: note.id, kind: "Photo" },
      },
    });
    expect(shared.state.lastSeq).toBe(1);
    expect(shared.state.cat?.lastSeq).toBe(1);
  });
});

describe("the temper", () => {
  const replay = (events: ReadonlyArray<readonly [CatEvent, number]>): CatTemper => {
    let temper = newTemper;
    let previous: EpochMillis | undefined;
    for (const [event, at] of events) {
      temper = nextTemper(temper, event, at, previous);
      previous = at;
    }
    return temper;
  };

  it("drifts slowly: fifty pets warm the cat, but never past the bound", () => {
    const pets = Array.from(
      { length: 50 },
      (_, i) => [{ _tag: "Petted" }, start + i * hour] as const,
    );
    const fifty = replay(pets);
    expect(fifty.cuddly).toBeGreaterThan(0.75);
    expect(fifty.cuddly).toBeLessThan(temperHigh);
    const thousand = replay(
      Array.from({ length: 1000 }, (_, i) => [{ _tag: "Petted" }, start + i * hour] as const),
    );
    expect(thousand.cuddly).toBeLessThanOrEqual(temperHigh);
    expect(replay([[{ _tag: "Petted" }, start]]).cuddly - newTemper.cuddly).toBeCloseTo(0.008, 9);
  });

  it("games make it curious and lively, shooing makes it keep away", () => {
    const games = replay(
      Array.from(
        { length: 30 },
        (_, i) =>
          [
            Schema.decodeSync(CatEvent)({ _tag: "GamePlayed", game: "laser", score: 3, won: true }),
            start + i * hour,
          ] as const,
      ),
    );
    expect(games.curious).toBeGreaterThan(0.6);
    expect(games.lazy).toBeLessThan(0.45);
    const shooed = replay(
      Array.from({ length: 200 }, (_, i) => [{ _tag: "Shooed" }, start + i * hour] as const),
    );
    expect(shooed.cuddly).toBeGreaterThanOrEqual(temperLow);
    expect(shooed.cuddly).toBeLessThan(0.2);
  });

  it("cools when left alone for days, up to a week", () => {
    const warm = { ...newTemper, cuddly: 0.8 };
    const soon = nextTemper(warm, { _tag: "Watered" }, start + 23 * hour, start);
    const later = nextTemper(warm, { _tag: "Watered" }, start + 3 * day, start);
    const month = nextTemper(warm, { _tag: "Watered" }, start + 30 * day, start);
    const week = nextTemper(warm, { _tag: "Watered" }, start + 7 * day, start);
    expect(soon.cuddly).toBe(0.8);
    expect(later.cuddly).toBeLessThan(0.8);
    expect(month.cuddly).toBe(week.cuddly);
  });
});

describe("the needs", () => {
  const partners = [alice, bob] as const;
  const context = { partners, utcOffsetSeconds: 0, bornAt: start };
  const entry = (n: number, by: UserId, at: number, event: CatEvent): CatEntry => ({
    seq: n,
    id: uuid(n),
    by,
    at,
    event,
  });

  it("starts at the initial values when nothing has happened since birth", () => {
    // The fold walks a 15-minute grid from below the birth, as Swift's does: born on the grid.
    const onGrid = Math.floor(start / (15 * 60_000)) * 15 * 60_000;
    const needs = catNeeds([], onGrid, { ...context, bornAt: onGrid });
    expect(needs.full).toBeCloseTo(lifeConfig.initial, 9);
    expect(needs.playful).toBeCloseTo(lifeConfig.initial, 9);
    expect(needs.loved).toBeCloseTo(lifeConfig.initial, 9);
    expect(needs.missing).toBeUndefined();
  });

  it("a meal fills Full, and a note fills Loved for both partners", () => {
    const at = start + 2 * hour;
    const hungry = catNeeds([], at + hour, context);
    const fed = catNeeds([entry(1, alice, at, { _tag: "Fed", grams: 30 })], at + hour, context);
    expect(fed.full).toBeGreaterThan(hungry.full);
    const note = catNeeds(
      [entry(1, alice, at, { _tag: "NoteShared", note: photoFrom(alice).id, kind: "Photo" })],
      at + hour,
      context,
    );
    expect(note.loved).toBeGreaterThan(hungry.loved);
    expect(note.missing).toBeUndefined();
  });

  it("misses the partner who never pets it", () => {
    const pets = Array.from({ length: 16 }, (_, i) =>
      entry(i + 1, alice, start + (i + 1) * (hour / 2), { _tag: "Petted" }),
    );
    expect(catNeeds(pets, start + 10 * hour, context).missing).toBe(bob);
    expect(catNeeds(pets.slice(0, 2), start + 2 * hour, context).missing).toBeUndefined();
  });

  it("counts an entry once, ignores the plant, and reads only the last week", () => {
    const fed = entry(1, alice, start + hour, { _tag: "Fed", grams: 30 });
    const now = start + 2 * hour;
    expect(catNeeds([fed, fed], now, context)).toEqual(catNeeds([fed], now, context));
    expect(catNeeds([fed, entry(2, bob, start + hour, { _tag: "Watered" })], now, context)).toEqual(
      catNeeds([fed], now, context),
    );
    const later = start + 10 * day;
    expect(catNeeds([fed], later, context)).toEqual(catNeeds([], later, context));
  });

  /**
   * Golden values the Swift `PetLife` must reproduce within 1e-9 for the same journal, with
   * `LifeContext(partners: ["user-alice", "user-bob"], utcOffset: 3600, born: start)` and each
   * entry as a `LifeEvent` with its `id`, `by` and whole-second `at`.
   */
  it("matches the golden vectors", async () => {
    const journal: ReadonlyArray<CatEntry> = [
      entry(1, alice, start + 1 * hour, { _tag: "Fed", grams: 40 }),
      entry(2, bob, start + 2 * hour, { _tag: "Petted" }),
      entry(
        3,
        alice,
        start + 5 * hour,
        Schema.decodeSync(CatEvent)({ _tag: "GamePlayed", game: "laser", score: 7, won: true }),
      ),
      entry(4, bob, start + 9 * hour, {
        _tag: "NoteShared",
        note: photoFrom(bob).id,
        kind: "Text",
      }),
      entry(5, alice, start + 20 * hour, { _tag: "Slept" }),
      entry(6, bob, start + 26 * hour, { _tag: "Played" }),
      entry(7, alice, start + 30 * hour, { _tag: "Shooed" }),
      entry(8, alice, start + 31 * hour, { _tag: "Watered" }),
    ];
    const golden = { ...context, utcOffsetSeconds: 3600 };
    const times = [0, 3, 8, 12, 24, 36, 72, 200].map((h) => start + h * hour + 1234);
    const vectors = {
      context: golden,
      journal: Schema.encodeSync(Schema.Array(CatEntry))(journal),
      needs: Schema.encodeSync(Schema.Array(CatNeeds))(
        times.map((now) => catNeeds(journal, now, golden)),
      ),
    };
    await expect(`${JSON.stringify(vectors, null, 2)}\n`).toMatchFileSnapshot(
      "./golden/cat-life.json",
    );
  });
});

describe("RoomService: the cat", () => {
  const saveRequest = (name = "Mochi"): SaveCatRequest => ({
    name: Schema.decodeSync(SaveCatName)(name),
    look: catProfile.look,
    utcOffsetSeconds: 0,
  });
  const recordRequest = (n: number, event: CatEvent = { _tag: "Petted" }) =>
    Schema.decodeSync(RecordCatEventRequest)({ id: uuid(n), event });

  const run = <A, E>(
    store: ReturnType<typeof memoryStore>,
    program: Effect.Effect<A, E, RoomService>,
  ): Promise<A> =>
    Effect.runPromise(
      TestClock.setTime(start).pipe(
        Effect.andThen(program),
        Effect.provide(
          Layer.merge(
            RoomService.layer.pipe(Layer.provide(Layer.merge(store.layer, countingIds()))),
            TestClock.layer(),
          ),
        ),
      ),
    );

  const opened = RoomService.use((room) =>
    room.dispatch(RoomCommand.cases.Open.make({ pairId, members: [alice, bob] })),
  );

  it("adopts at the room's clock and journals care with the room's time", async () => {
    const store = memoryStore();
    const result = await run(
      store,
      RoomService.use((room) =>
        Effect.gen(function* () {
          yield* opened;
          const before = yield* room.recordCatEvent(alice, recordRequest(1));
          yield* TestClock.adjust(Duration.minutes(5));
          yield* room.saveCat(alice, saveRequest(), catProfile.natureSeed);
          yield* TestClock.adjust(Duration.hours(1));
          const petted = yield* room.recordCatEvent(bob, recordRequest(2));
          const again = yield* room.recordCatEvent(bob, recordRequest(2));
          const stolen = yield* room.recordCatEvent(alice, recordRequest(2));
          const view = yield* room.catView;
          return { before, petted, again, stolen, view };
        }),
      ),
    );
    expect(result.before).toEqual({ _tag: "Rejected", rejection: { _tag: "CatNotAdopted" } });
    expect(result.view?.cat?.bornAt).toBe(start + 5 * 60_000);
    expect(
      result.petted._tag === "Accepted" &&
        result.petted.outputs.filter((o) => o._tag !== "CoinsEntered"),
    ).toEqual([
      {
        _tag: "CatEntryAppended",
        entry: { seq: 1, id: uuid(2), by: bob, at: start + 65 * 60_000, event: { _tag: "Petted" } },
      },
    ]);
    expect(result.again._tag === "Accepted" && result.again.outputs[0]?._tag).toBe(
      "CatEntryRepeated",
    );
    expect(result.stolen).toEqual({ _tag: "Rejected", rejection: { _tag: "CatEntryIdTaken" } });
    expect(store.memory.cat).toHaveLength(1);
    expect(result.view?.lastSeq).toBe(1);
    expect(result.view?.needs.at).toBe(start + 65 * 60_000);
  });

  it("journals a note once the cat exists, and forgets the cat when the pair ends", async () => {
    const store = memoryStore();
    const photo = SendNoteRequest.cases.Photo.make({
      key: uuid(40),
      image,
      width: 1200,
      height: 1600,
      preview: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
    });
    const result = await run(
      store,
      RoomService.use((room) =>
        Effect.gen(function* () {
          yield* opened;
          yield* room.saveCat(bob, saveRequest(), catProfile.natureSeed);
          yield* room.sendNote(alice, photo);
          yield* room.sendNote(alice, photo);
          const journal = yield* room.catEntriesAfter(0, 10);
          yield* room.forgetAuthor(alice);
          const after = yield* room.catView;
          return { journal, after };
        }),
      ),
    );
    expect(result.journal.map((e) => e.event._tag)).toEqual(["NoteShared"]);
    expect(result.after?.cat).toBeUndefined();
    expect(store.memory.cat).toEqual([]);
  });
});
