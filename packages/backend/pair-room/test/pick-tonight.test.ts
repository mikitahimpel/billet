import { Effect, Layer } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import type { UserId } from "@billet/contracts-domain/ids";
import type { ListItemId } from "@billet/contracts-domain/list";
import type { PickChoice, PickTitle } from "@billet/contracts-domain/pick-tonight";
import {
  decidePick,
  type PickRow,
  PickTonightRoom,
  PickTonightStore,
  pickKeyOf,
  pickSessionMillis,
  pickView,
} from "../src/pick-tonight.ts";
import { RoomStore } from "../src/room-store.ts";
import { active, alice, bob, mallory, uuid, vacant } from "./samples.ts";

const arrival: PickTitle = { _tag: "Title", kind: "movie", tmdb: 329865 };
const listed: PickTitle = { _tag: "Item", item: uuid(1) as unknown as ListItemId };

const swipe = (title: PickTitle, choice: PickChoice) => ({ title, choice, name: "Arrival" });

/** Swipes in order, each `step` after the one before, through the pure rules. */
const play = (moves: ReadonlyArray<readonly [UserId, PickChoice, number?]>, title = arrival) => {
  let rows: ReadonlyArray<PickRow> = [];
  let at = 1_000;
  const matches: Array<number> = [];
  for (const [by, choice, step = 60_000] of moves) {
    at += step;
    const { write, match } = decidePick(rows, by, swipe(title, choice), at);
    if (write !== undefined) {
      rows = [...rows.filter((row) => !(row.member === by && sameKey(row, write))), write];
    }
    if (match !== undefined) matches.push(match.at);
  }
  return { rows, matches, at };
};

const sameKey = (a: PickRow, b: PickRow) => pickKeyOf(a.title) === pickKeyOf(b.title);

describe("a Pick tonight match", () => {
  it("needs a ♥ from both partners", () => {
    expect(
      play([
        [alice, "want"],
        [bob, "want"],
      ]).matches,
    ).toHaveLength(1);
    expect(
      play([
        [alice, "want"],
        [bob, "pass"],
      ]).matches,
    ).toEqual([]);
    expect(
      play([
        [alice, "seen"],
        [bob, "want"],
      ]).matches,
    ).toEqual([]);
    expect(
      play([
        [alice, "want"],
        [alice, "want"],
      ]).matches,
    ).toEqual([]);
  });

  it("is made once: a repeated ♥ changes nothing", () => {
    const { rows, matches } = play([
      [alice, "want"],
      [bob, "want"],
      [bob, "want"],
      [alice, "want"],
    ]);
    expect(matches).toHaveLength(1);
    expect(rows).toHaveLength(2);
    expect(decidePick(rows, bob, swipe(arrival, "want"), 999_999)).toEqual({});
  });

  it("is lost when a partner changes their mind, and made again by a new ♥", () => {
    const { rows, matches, at } = play([
      [alice, "want"],
      [bob, "want"],
      [alice, "pass"],
      [alice, "want"],
    ]);
    expect(matches).toHaveLength(2);
    expect(pickView(rows, alice, at).matches).toHaveLength(1);
  });

  it("needs both ♥ within 24 hours", () => {
    expect(
      play([
        [alice, "want"],
        [bob, "want", pickSessionMillis],
      ]).matches,
    ).toEqual([]);
    expect(
      play([
        [alice, "want"],
        [bob, "want", pickSessionMillis - 1],
      ]).matches,
    ).toHaveLength(1);
  });

  it("starts a new session once a day has passed, so the same card can be swiped again", () => {
    const { rows, at } = play([[alice, "want"]]);
    expect(decidePick(rows, alice, swipe(arrival, "want"), at + 1)).toEqual({});
    const later = decidePick(rows, alice, swipe(arrival, "want"), at + pickSessionMillis);
    expect(later.write?.at).toBe(at + pickSessionMillis);
  });

  it("is per card: a list item and a TMDB title never match each other", () => {
    const first = decidePick([], alice, swipe(listed, "want"), 1);
    expect(first.write).toBeDefined();
    expect(decidePick([first.write!], bob, swipe(arrival, "want"), 2).match).toBeUndefined();
    expect(decidePick([first.write!], bob, swipe(listed, "want"), 2).match).toEqual({
      title: listed,
      name: "Arrival",
      at: 2,
    });
  });
});

describe("the session view", () => {
  it("shows the caller's own swipes, how far the partner got and the matches", () => {
    const { rows, at } = play([
      [alice, "want"],
      [bob, "want"],
    ]);
    const other = decidePick(rows, bob, swipe({ ...arrival, tmdb: 2 }, "pass"), at).write!;
    const view = pickView([...rows, other], alice, at);
    expect(view.swipes).toEqual([{ title: arrival, choice: "want", at: at - 60_000 }]);
    expect(view.partnerPicked).toBe(2);
    expect(view.matches).toEqual([{ title: arrival, name: "Arrival", at }]);
    expect(pickView(rows, alice, at + pickSessionMillis)).toEqual({
      swipes: [],
      partnerPicked: 0,
      matches: [],
    });
  });
});

describe("PickTonightRoom", () => {
  const roomWith = (state: typeof active | typeof vacant) => {
    let rows: ReadonlyArray<PickRow> = [];
    const store = Layer.succeed(PickTonightStore, {
      since: (since) => Effect.sync(() => rows.filter((row) => row.at >= since)),
      put: (row, pruneBefore) =>
        Effect.sync(() => {
          rows = [
            ...rows.filter(
              (old) => old.at >= pruneBefore && !(old.member === row.member && sameKey(old, row)),
            ),
            row,
          ];
        }),
      forget: Effect.sync(() => void (rows = [])),
    });
    const room = Layer.succeed(RoomStore, {
      load: Effect.succeed(state),
    } as unknown as RoomStore["Service"]);
    return {
      pick: Effect.runSync(PickTonightRoom.make.pipe(Effect.provide(Layer.merge(store, room)))),
      rows: () => rows,
    };
  };

  const at =
    (millis: number) =>
    <A>(effect: Effect.Effect<A>) =>
      Effect.runPromise(
        TestClock.setTime(millis).pipe(Effect.andThen(effect), Effect.provide(TestClock.layer())),
      );

  it("answers the match to the swipe that made it, and tells the partner who swiped first", async () => {
    const { pick } = roomWith(active);
    await at(10_000)(pick.run(alice, { _tag: "Swipe", ...swipe(arrival, "want") }));
    const second = await at(20_000)(pick.run(bob, { _tag: "Swipe", ...swipe(arrival, "want") }));
    expect(second._tag === "Done" && second.view.match).toEqual({
      title: arrival,
      name: "Arrival",
      at: 20_000,
    });
    expect(await at(20_000)(pick.notice(pickKeyOf(arrival), 20_000))).toEqual({
      recipient: alice,
      match: { title: arrival, name: "Arrival", at: 20_000 },
    });
    await at(30_000)(pick.run(alice, { _tag: "Swipe", ...swipe(arrival, "pass") }));
    expect(await at(30_000)(pick.notice(pickKeyOf(arrival), 20_000))).toBeUndefined();
  });

  it("forgets swipes older than a session on the next swipe", async () => {
    const { pick, rows } = roomWith(active);
    await at(10_000)(pick.run(alice, { _tag: "Swipe", ...swipe(arrival, "want") }));
    await at(10_001 + pickSessionMillis)(
      pick.run(bob, { _tag: "Swipe", ...swipe(listed, "pass") }),
    );
    expect(rows().map((row) => row.member)).toEqual([bob]);
  });

  it("refuses a caller who is not a member, and a room not open", async () => {
    expect(await at(1)(roomWith(active).pick.run(mallory, { _tag: "View" }))).toEqual({
      _tag: "Refused",
      reason: "NotOpen",
    });
    const closed = await at(1)(roomWith(vacant).pick.run(alice, { _tag: "View" }));
    expect(closed._tag).toBe("Refused");
  });
});
