import { Effect, Layer, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { type SchoolTrick, TrickId } from "@billet/contracts-domain/school";
import { RoomStore } from "../src/room-store.ts";
import {
  decideLesson,
  routineIsKnown,
  type SchoolRows,
  SchoolRoom,
  SchoolStore,
  schoolTricksInAll,
  schoolView,
} from "../src/school.ts";
import { active, alice, bob, mallory, vacant } from "./samples.ts";

const id = Schema.decodeUnknownSync(TrickId);
const spin = id("spin");
const known = (stars: number, by = alice): SchoolTrick => ({ trick: spin, stars, by, at: 1 });
const steps = (...tricks: ReadonlyArray<string>) =>
  tricks.map((trick, index) => ({ trick: id(trick), landed: index % 2 === 0 }));

describe("lessons", () => {
  it("earn the first star for the teacher", () => {
    expect(decideLesson([], alice, { trick: spin, stars: 1 }, 5)).toEqual({
      _tag: "Write",
      write: { trick: spin, stars: 1, by: alice, at: 5 },
    });
  });

  it("add one star at a time, from either partner, and keep the first teacher", () => {
    expect(decideLesson([known(1)], bob, { trick: spin, stars: 2 }, 7)).toEqual({
      _tag: "Write",
      write: { trick: spin, stars: 2, by: alice, at: 7 },
    });
  });

  it("change nothing for a star already held, so a retry is safe and a star is never lost", () => {
    expect(decideLesson([known(2)], bob, { trick: spin, stars: 2 }, 7)).toEqual({ _tag: "Keep" });
    expect(decideLesson([known(3)], bob, { trick: spin, stars: 1 }, 7)).toEqual({ _tag: "Keep" });
  });

  it("refuse a skipped star", () => {
    expect(decideLesson([], alice, { trick: spin, stars: 2 }, 5)).toEqual({ _tag: "Invalid" });
    expect(decideLesson([known(1)], alice, { trick: spin, stars: 3 }, 5)).toEqual({
      _tag: "Invalid",
    });
  });

  it("refuse a new trick past the bound, and still raise one already known", () => {
    const full = Array.from({ length: schoolTricksInAll }, (_, index) => ({
      ...known(1),
      trick: id(`trick-${index}`),
    }));
    expect(decideLesson(full, alice, { trick: spin, stars: 1 }, 5)).toEqual({ _tag: "Invalid" });
    expect(decideLesson(full, alice, { trick: id("trick-0"), stars: 2 }, 5)._tag).toBe("Write");
  });
});

describe("routines", () => {
  it("hold only tricks the cat knows", () => {
    expect(routineIsKnown([known(1)], { steps: steps("spin", "spin", "spin") })).toBe(true);
    expect(routineIsKnown([known(1)], { steps: steps("spin", "sit", "spin") })).toBe(false);
  });

  it("show each partner their own and the other's", () => {
    const rows: SchoolRows = {
      tricks: [known(1)],
      routines: [{ member: alice, steps: steps("spin", "spin", "spin"), at: 9 }],
    };
    expect(schoolView(rows, alice)).toEqual({
      tricks: [known(1)],
      mine: { steps: steps("spin", "spin", "spin"), at: 9 },
    });
    expect(schoolView(rows, bob)).toEqual({
      tricks: [known(1)],
      partner: { steps: steps("spin", "spin", "spin"), at: 9 },
    });
  });
});

describe("SchoolRoom", () => {
  const roomWith = (state: typeof active | typeof vacant) => {
    let rows: SchoolRows = { tricks: [], routines: [] };
    const store = Layer.succeed(SchoolStore, {
      all: Effect.sync(() => rows),
      putTrick: (row) =>
        Effect.sync(() => {
          rows = { ...rows, tricks: [...rows.tricks.filter((r) => r.trick !== row.trick), row] };
        }),
      putRoutine: (row) =>
        Effect.sync(() => {
          const routines = [...rows.routines.filter((r) => r.member !== row.member), row];
          rows = { ...rows, routines };
        }),
      forget: Effect.sync(() => void (rows = { tricks: [], routines: [] })),
    });
    const room = Layer.succeed(RoomStore, {
      load: Effect.succeed(state),
    } as unknown as RoomStore["Service"]);
    return Effect.runSync(SchoolRoom.make.pipe(Effect.provide(Layer.merge(store, room))));
  };

  it("teaches, takes a routine of known tricks, replaces it, and forgets", async () => {
    const room = roomWith(active);
    const run = (by: typeof alice, command: Parameters<typeof room.run>[1]) =>
      Effect.runPromise(room.run(by, command));

    await run(alice, { _tag: "Lesson", trick: spin, stars: 1 });
    expect(await run(bob, { _tag: "Routine", steps: steps("spin", "sit", "spin") })).toEqual({
      _tag: "Refused",
      reason: "Invalid",
    });
    await run(bob, { _tag: "Routine", steps: steps("spin", "spin", "spin") });
    const second = steps("spin", "spin", "spin", "spin");
    await run(bob, { _tag: "Routine", steps: second });
    expect(await run(alice, { _tag: "View" })).toMatchObject({
      _tag: "Done",
      view: { tricks: [{ trick: spin, stars: 1, by: alice }], partner: { steps: second } },
    });

    await Effect.runPromise(room.forget);
    expect(await run(alice, { _tag: "View" })).toEqual({ _tag: "Done", view: { tricks: [] } });
  });

  it("is closed to a stranger and to a room that is not open", async () => {
    const refused = { _tag: "Refused", reason: "NotOpen" };
    expect(await Effect.runPromise(roomWith(active).run(mallory, { _tag: "View" }))).toEqual(
      refused,
    );
    expect(await Effect.runPromise(roomWith(vacant).run(alice, { _tag: "View" }))).toEqual(refused);
  });
});
