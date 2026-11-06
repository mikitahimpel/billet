import { Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { CatEvent } from "@billet/contracts-domain/cat";
import { rewardFor } from "@billet/contracts-domain/coins";
import type { UserId } from "@billet/contracts-domain/ids";
import { RiddleWord } from "@billet/contracts-domain/riddle";
import {
  decideGiveUp,
  decideGuess,
  decideHint,
  decideSend,
  decoysOf,
  noRiddleSeries,
  type RiddleRow,
  riddleView,
  solveReward,
  tilesFor,
} from "../src/riddle-rules.ts";
import { RiddleRoom, type RiddleCommand } from "../src/riddle.ts";
import { RoomService } from "../src/room-service.ts";
import type { ActiveRoom } from "../src/room-state.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import {
  active,
  alice,
  bob,
  mallory,
  riddleId,
  riddleImage,
  riddleOf,
  uuid,
  withCat,
} from "./samples.ts";

const at = 1_700_000_100_000;
const word = Schema.decodeSync(RiddleWord);
const compact = { version: 1, strokes: [] } as const;

const send = (n: number, text: string) => ({
  id: riddleId(n),
  word: text,
  compact,
  image: riddleImage,
});

/** Applies every hint `row` allows, through the pure rules, and returns the rows in between. */
const hinted = (row: RiddleRow): ReadonlyArray<RiddleRow> => {
  const rows: Array<RiddleRow> = [];
  let current = row;
  for (;;) {
    const decision = decideHint(current, bob);
    if (decision._tag !== "Stored") return rows;
    current = decision.write.riddle;
    rows.push(current);
  }
};

describe("the tiles", () => {
  it("are the word's letters and decoys, twelve in all, the same for the same seed", () => {
    const tiles = tilesFor(word("north pole"), "seed");
    expect(tiles).toHaveLength(12);
    expect(tilesFor(word("north pole"), "seed")).toEqual(tiles);
    expect(decoysOf({ word: word("north pole"), tiles })).toHaveLength(3);
    const letters = tiles.filter(
      (_, index) => !decoysOf({ word: word("north pole"), tiles }).includes(index),
    );
    expect(letters.toSorted()).toEqual([..."northpole"].toSorted());
  });

  it("keep two decoys for a word of eleven or twelve letters", () => {
    expect(tilesFor(word("hippopotamus"), "seed")).toHaveLength(14);
    expect(tilesFor(word("caterpillar"), "seed")).toHaveLength(13);
  });
});

describe("a send", () => {
  it("normalises the word and refuses one that is not a riddle word", () => {
    const sent = decideSend(undefined, [], alice, send(1, "  North Pole "), at);
    expect(sent._tag === "Stored" && sent.write.riddle.word).toBe("north pole");
    for (const bad of ["", "cat2", "a  b", "abcdefghijklm", "ёж"]) {
      expect(decideSend(undefined, [], alice, send(1, bad), at), bad).toEqual({
        _tag: "Refused",
        reason: "BadWord",
      });
    }
  });

  it("allows one open riddle per drawer, and answers a retry with the first", () => {
    const open = [riddleOf(alice, "cat", 1)];
    expect(decideSend(undefined, open, alice, send(2, "dog"), at)).toEqual({
      _tag: "Refused",
      reason: "RiddleOpen",
    });
    expect(decideSend(undefined, open, bob, send(2, "dog"), at)._tag).toBe("Stored");
    expect(decideSend(open[0], open, alice, send(1, "dog"), at)).toEqual({
      _tag: "Repeated",
      riddle: open[0],
    });
    expect(decideSend(open[0], open, bob, send(1, "dog"), at)).toMatchObject({
      reason: "IdTaken",
    });
  });
});

describe("the riddle as each member sees it", () => {
  it("hides the word from the guesser until the round ends", () => {
    const row = riddleOf(alice, "cat");
    expect(riddleView(row, alice).word).toBe("cat");
    const guesser = riddleView(row, bob);
    expect(guesser.word).toBeUndefined();
    expect(guesser.shape).toEqual([3]);
    expect(JSON.stringify(guesser)).not.toContain('"cat"');
    const ended = decideGiveUp(row, noRiddleSeries, bob, at);
    if (ended._tag !== "Stored") throw new Error(ended._tag);
    expect(riddleView(ended.write.riddle, bob).word).toBe("cat");
  });
});

describe("a try", () => {
  const key = uuid(1);

  it("is the guesser's alone, counts each try and compares normalised", () => {
    const row = riddleOf(alice, "north pole");
    expect(decideGuess(row, undefined, noRiddleSeries, alice, { key, guess: "x" }, at)).toEqual({
      _tag: "Refused",
      reason: "NotGuesser",
    });
    const wrong = decideGuess(row, undefined, noRiddleSeries, bob, { key, guess: "south" }, at);
    expect(wrong).toMatchObject({ _tag: "Stored", right: false, write: { riddle: { tries: 1 } } });
    expect(wrong._tag === "Stored" && wrong.reward).toBeUndefined();
    const right = decideGuess(
      row,
      undefined,
      noRiddleSeries,
      bob,
      { key, guess: " North Pole" },
      at,
    );
    expect(right).toMatchObject({
      _tag: "Stored",
      right: true,
      write: { riddle: { state: { _tag: "Solved", at } }, series: { series: 1, best: 1 } },
      reward: { won: true, score: 10 },
    });
  });

  it("answers a repeated key with its first result, even once the round ended", () => {
    const solved: RiddleRow = { ...riddleOf(alice), state: { _tag: "Solved", at } };
    const earlier = { riddle: solved.id, key, right: true, at };
    expect(decideGuess(solved, earlier, noRiddleSeries, bob, { key, guess: "dog" }, at)).toEqual({
      _tag: "Repeated",
      riddle: solved,
      right: true,
    });
    expect(
      decideGuess(solved, undefined, noRiddleSeries, bob, { key: uuid(2), guess: "cat" }, at),
    ).toEqual({ _tag: "Refused", reason: "RiddleClosed" });
  });
});

describe("hints", () => {
  it("halve the decoys first, then show one letter at a time, all but one", () => {
    const row = riddleOf(alice, "rabbit");
    const steps = hinted(row);
    expect(steps).toHaveLength(6);
    const [first] = steps;
    expect(first?.removed).toHaveLength(3);
    expect(first?.removed.every((index) => decoysOf(row).includes(index))).toBe(true);
    expect(first?.revealed).toEqual([]);
    const last = steps.at(-1)!;
    expect(last.hints).toBe(6);
    expect(last.revealed).toHaveLength(5);
    expect(new Set(last.revealed.map((letter) => letter.index)).size).toBe(5);
    for (const { index, letter } of last.revealed) expect("rabbit"[index]).toBe(letter);
    expect(decideHint(last, bob)).toEqual({ _tag: "Refused", reason: "NoHint" });
    expect(hinted(row)).toEqual(steps);
  });

  it("give a one-letter word only the decoys", () => {
    expect(hinted(riddleOf(alice, "i"))).toHaveLength(1);
    expect(decideHint(riddleOf(alice), alice)).toMatchObject({ reason: "NotGuesser" });
  });

  it("lower a solve's coins by two each, to no fewer than four", () => {
    expect([0, 1, 2, 3, 4, 9].map((hints) => solveReward(hints).score)).toEqual([
      10, 8, 6, 4, 4, 4,
    ]);
  });
});

describe("a give-up", () => {
  it("shows the word, pays three and starts the series again, keeping the best", () => {
    const decision = decideGiveUp(riddleOf(alice), { series: 4, best: 7 }, bob, at);
    expect(decision).toMatchObject({
      _tag: "Stored",
      write: { riddle: { state: { _tag: "GivenUp", at } }, series: { series: 0, best: 7 } },
      reward: { won: false, score: 3 },
    });
  });
});

describe("the reward", () => {
  it("is the round's own score in the games cap", () => {
    const played = (score: number, won: boolean) =>
      rewardFor(
        Schema.decodeSync(CatEvent)({ _tag: "GamePlayed", game: "draw-guess", score, won }),
      );
    expect(played(6, true)).toEqual({ source: "games", coins: 6 });
    expect(played(3, false)).toEqual({ source: "games", coins: 3 });
    expect(
      rewardFor(
        Schema.decodeSync(CatEvent)({ _tag: "GamePlayed", game: "laser", score: 6, won: true }),
      ),
    ).toEqual({ source: "games", coins: 10 });
  });
});

describe("RiddleRoom", () => {
  const roomWith = (state: ActiveRoom) => {
    const rooms = memoryStore();
    rooms.memory.state = state;
    const service = Effect.runSync(
      RoomService.make.pipe(Effect.provide(Layer.merge(rooms.layer, countingIds()))),
    );
    const riddles = Effect.runSync(
      RiddleRoom.make.pipe(
        Effect.provide(
          Layer.mergeAll(rooms.layer, rooms.riddleLayer, Layer.succeed(RoomService, service)),
        ),
      ),
    );
    const run = (by: UserId, command: RiddleCommand, millis = at) =>
      Effect.runPromise(
        TestClock.setTime(millis).pipe(
          Effect.andThen(riddles.run(by, command)),
          Effect.provide(TestClock.layer()),
        ),
      );
    const record = (event: CatEvent) =>
      Effect.runPromise(service.recordCatEvent(bob, { id: uuid(77), event }));
    return { run, rooms, record };
  };

  const sendCommand = (n: number, text: string): RiddleCommand => ({
    _tag: "Send",
    ...send(n, text),
  });
  const guess = (n: number, key: number, text: string): RiddleCommand => ({
    _tag: "Guess",
    riddle: riddleId(n),
    key: uuid(key),
    guess: text,
  });

  it("keeps the word from the guesser and refuses a second open riddle", async () => {
    const { run } = roomWith(withCat);
    const sent = await run(alice, sendCommand(1, "Cat"));
    expect(sent.push?.kind).toBe("sent");
    expect(sent.result).toMatchObject({ _tag: "Changed", riddle: { word: "cat" } });
    expect((await run(alice, sendCommand(2, "dog"))).result).toEqual({
      _tag: "Refused",
      reason: "RiddleOpen",
    });
    const listed = await run(bob, { _tag: "View" });
    if (listed.result._tag !== "Listed") throw new Error(listed.result._tag);
    expect(listed.result.view.open).toHaveLength(1);
    expect(listed.result.view.open[0]?.word).toBeUndefined();
    expect(JSON.stringify(listed.result.view)).not.toContain('"cat"');
    expect((await run(mallory, { _tag: "View" })).result).toMatchObject({ reason: "NotOpen" });
  });

  it("journals the guesser's GamePlayed with the coins in the same write, once", async () => {
    const { run, rooms } = roomWith(withCat);
    await run(alice, sendCommand(1, "cat"));
    await run(bob, { _tag: "Hint", riddle: riddleId(1) });
    const wrong = await run(bob, guess(1, 1, "dog"));
    expect(wrong.result).toMatchObject({ right: false, riddle: { tries: 1 } });
    expect(rooms.memory.cat).toEqual([]);
    const solved = await run(bob, guess(1, 2, "CAT"));
    expect(solved.result).toMatchObject({ right: true, riddle: { tries: 2, word: "cat" } });
    expect(solved.push?.kind).toBe("ended");
    expect(rooms.memory.cat.map((entry) => [entry.by, entry.event])).toEqual([
      [bob, { _tag: "GamePlayed", game: "draw-guess", score: 8, won: true }],
    ]);
    expect(rooms.memory.coins.map((entry) => [entry.id, entry.amount])).toEqual([
      [`earn:${riddleId(1)}`, 8],
    ]);

    const again = await run(bob, guess(1, 2, "whatever"));
    expect(again.result).toMatchObject({ right: true, riddle: { tries: 2 } });
    expect(again.changed).toBeUndefined();
    expect(again.push?.kind).toBe("ended");
    expect(rooms.memory.cat).toHaveLength(1);
    expect(rooms.memory.coins).toHaveLength(1);
    expect((await run(bob, guess(1, 3, "cat"))).result).toMatchObject({ reason: "RiddleClosed" });
  });

  it("pays a pair without a cat yet, and keeps the series until a give-up", async () => {
    const { run, rooms } = roomWith(active);
    await run(alice, sendCommand(1, "cat"));
    await run(bob, guess(1, 1, "cat"), at + 1);
    await run(bob, sendCommand(2, "dog"));
    await run(alice, guess(2, 2, "dog"), at + 2);
    await run(alice, sendCommand(3, "fish"));
    const series = await run(alice, { _tag: "View" });
    expect(series.result).toMatchObject({
      view: { series: 2, best: 2, open: [{ drawer: alice }] },
    });
    const gaveUp = await run(bob, { _tag: "GiveUp", riddle: riddleId(3) }, at + 3);
    expect(gaveUp.result).toMatchObject({ riddle: { word: "fish", state: { _tag: "GivenUp" } } });
    expect(gaveUp.push?.kind).toBe("ended");
    const after = await run(bob, { _tag: "View" });
    if (after.result._tag !== "Listed") throw new Error(after.result._tag);
    expect(after.result.view).toMatchObject({ series: 0, best: 2, open: [] });
    expect(after.result.view.ended.map((riddle) => riddle.word)).toEqual(["fish", "dog", "cat"]);
    expect(rooms.memory.coins.map((entry) => entry.amount)).toEqual([10, 10, 3]);
  });

  it("refuses an app's GamePlayed for draw-guess, and takes other games", async () => {
    const { record } = roomWith(withCat);
    const game = (name: string) =>
      Schema.decodeSync(CatEvent)({ _tag: "GamePlayed", game: name, score: 10, won: true });
    expect(await record(game("draw-guess"))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "RoomJournalsGame" },
    });
    expect((await record(game("laser")))._tag).toBe("Accepted");
  });

  it("refuses a new riddle under an id a care entry already holds", async () => {
    const { run, record } = roomWith(withCat);
    await record({ _tag: "Petted" });
    const taken: RiddleCommand = { _tag: "Send", ...send(1, "cat"), id: riddleId(-8923) };
    expect((await run(alice, taken)).result).toEqual({ _tag: "Refused", reason: "IdTaken" });
  });

  it("still ends a riddle whose id a care entry took after it was sent, without paying", async () => {
    for (const end of ["solve", "give up"] as const) {
      const { run, rooms, record } = roomWith(withCat);
      const id = riddleId(-8923);
      await run(alice, { _tag: "Send", ...send(1, "cat"), id });
      expect((await record({ _tag: "Petted" }))._tag).toBe("Accepted");
      const ended =
        end === "solve"
          ? await run(bob, { _tag: "Guess", riddle: id, key: uuid(1), guess: "cat" })
          : await run(bob, { _tag: "GiveUp", riddle: id });
      expect(ended.result).toMatchObject({ riddle: { word: "cat" } });
      expect(rooms.memory.cat.map((entry) => entry.event._tag)).toEqual(["Petted"]);
      expect((await run(alice, { _tag: "View" })).result).toMatchObject({ view: { open: [] } });
    }
  });

  it("answers a riddle it does not hold with NotFound", async () => {
    const { run } = roomWith(active);
    expect((await run(bob, guess(9, 1, "cat"))).result).toMatchObject({ reason: "NotFound" });
  });
});
