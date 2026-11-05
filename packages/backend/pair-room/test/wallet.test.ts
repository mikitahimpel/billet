import { Duration, Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { CatGameId, type CatEvent } from "@billet/contracts-domain/cat";
import { dailyEarnCaps, localDayOf } from "@billet/contracts-domain/coins";
import type { EpochMillis } from "@billet/contracts-domain/ids";
import { freeInk } from "@billet/contracts-domain/inks";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { decide } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import type { RoomDecision } from "../src/room-decision.ts";
import { RoomService } from "../src/room-service.ts";
import type { ActiveRoom } from "../src/room-state.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import {
  alice,
  bob,
  catProfile,
  mallory,
  pairId,
  photoFrom,
  rose,
  uuid,
  withCat,
} from "./samples.ts";

// 22:13 UTC, 23:13 on the cat's clock (UTC+1): its midnight is 47 minutes away.
const start: EpochMillis = 1_700_000_000_000;
const minute = 60_000;
const yarn = Schema.decodeSync(CatGameId)("yarn");

const care = (n: number, event: CatEvent = { _tag: "Petted" }, at = start) =>
  RoomCommand.cases.RecordCatEvent.make({ id: uuid(n), by: alice, at, event });

const accept = (room: ActiveRoom, command: RoomCommand): RoomDecision & { _tag: "Accepted" } => {
  const decision = decide(room, command);
  if (decision._tag !== "Accepted") throw new Error(`rejected: ${decision.rejection._tag}`);
  return decision;
};

const coinsOf = (decision: RoomDecision & { _tag: "Accepted" }) =>
  decision.outputs.flatMap((output) => (output._tag === "CoinsEntered" ? [output.entry] : []));

const after = (commands: ReadonlyArray<RoomCommand>, room: ActiveRoom = withCat) =>
  commands.reduce((state, command) => accept(state, command).state, room);

const buy = (n: number, ink = rose, by = alice) =>
  RoomCommand.cases.Buy.make({ id: uuid(n), by, ink, at: start });

describe("earning coins", () => {
  it("pays a journal entry its reward, under the entry's own id", () => {
    const decision = accept(withCat, care(1));
    expect(coinsOf(decision)).toEqual([
      { id: `earn:${uuid(1)}`, kind: "earn", amount: 1, ref: uuid(1), at: start },
    ]);
    expect(decision.state.wallet).toEqual({
      balance: 1,
      day: "2023-11-14",
      care: 1,
      notes: 0,
      games: 0,
      lists: 0,
    });
  });

  it.each([
    [{ _tag: "Fed", grams: 40 }, 1],
    [{ _tag: "Watered" }, 1],
    [{ _tag: "GamePlayed", game: yarn, score: 3, won: true }, 10],
    [{ _tag: "GamePlayed", game: yarn, score: 0, won: false }, 3],
    [{ _tag: "NoteShared", note: "note-1", kind: "Photo" }, 10],
    [{ _tag: "NoteShared", note: "note-1", kind: "Text" }, 5],
  ] as const)("%o earns %i", (event, coins) => {
    expect(coinsOf(accept(withCat, care(1, event as CatEvent))).map((e) => e.amount)).toEqual([
      coins,
    ]);
  });

  it("pays nothing for sleep and shooing", () => {
    const decision = accept(withCat, care(1, { _tag: "Slept" }));
    expect(coinsOf(decision)).toEqual([]);
    expect(decision.state.wallet.balance).toBe(0);
  });

  it("stops at the day's cap, and cuts the entry that crosses it", () => {
    const games = Array.from({ length: 5 }, (_, i) =>
      care(i + 1, { _tag: "GamePlayed", game: yarn, score: 1, won: true }),
    );
    const room = after(games.slice(0, 4));
    expect(room.wallet.games).toBe(dailyEarnCaps.games);
    expect(coinsOf(accept(room, games[4]!))).toEqual([]);

    const nearly = after(games.slice(0, 3));
    const lost = care(9, { _tag: "GamePlayed", game: yarn, score: 0, won: false });
    expect(coinsOf(accept(after([lost], nearly), games[3]!)).map((e) => e.amount)).toEqual([7]);
  });

  it("keeps each kind of care to its own cap", () => {
    const pets = Array.from({ length: dailyEarnCaps.care + 2 }, (_, i) => care(i + 1));
    const room = after(pets);
    expect(room.wallet).toMatchObject({ balance: dailyEarnCaps.care, care: dailyEarnCaps.care });
    const game = care(99, { _tag: "GamePlayed", game: yarn, score: 1, won: true });
    expect(coinsOf(accept(room, game)).map((e) => e.amount)).toEqual([10]);
  });

  it("starts the caps again at the cat's midnight, not UTC's", () => {
    const pets = Array.from({ length: dailyEarnCaps.care }, (_, i) => care(i + 1));
    const full = after(pets);
    // 23:00 UTC is still the 14th in UTC, and already the 15th on the cat's clock.
    const nextDay = care(50, { _tag: "Petted" }, start + 47 * minute);
    expect(localDayOf(start + 47 * minute, 0)).toBe("2023-11-14");
    const decision = accept(full, nextDay);
    expect(coinsOf(decision).map((e) => e.amount)).toEqual([1]);
    expect(decision.state.wallet).toEqual({
      balance: dailyEarnCaps.care + 1,
      day: "2023-11-15",
      care: 1,
      notes: 0,
      games: 0,
      lists: 0,
    });
  });

  it("pays a note shared with the cat", () => {
    const note = RoomCommand.cases.SendNote.make({
      key: uuid(7),
      note: photoFrom(bob, "note-7"),
    });
    expect(coinsOf(accept(withCat, note))).toMatchObject([{ id: `earn:${uuid(7)}`, amount: 10 }]);
  });
});

describe("buying an ink", () => {
  const rich: ActiveRoom = { ...withCat, wallet: { ...withCat.wallet, balance: 100 } };

  it("takes its price and gives the pair the ink, in one decision", () => {
    const decision = accept(rich, buy(1));
    expect(decision.outputs).toEqual([
      {
        _tag: "CoinsEntered",
        entry: { id: `spend:${uuid(1)}`, kind: "spend", amount: -60, ref: rose, at: start },
      },
      { _tag: "InksGranted", inks: [rose] },
      { _tag: "Purchased", id: uuid(1), by: alice, at: start, items: [rose], coins: 60 },
    ]);
    expect(decision.state.wallet.balance).toBe(40);
    expect(decision.state.inks).toEqual([rose]);
  });

  it("refuses what the pair cannot pay for, owns already, or does not belong to", () => {
    expect(decide(withCat, buy(1))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "NotEnoughCoins", needed: 60, have: 0 },
    });
    const owner = accept(rich, buy(1)).state;
    expect(decide(owner, buy(2))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "AlreadyOwned", ink: rose },
    });
    expect(decide(rich, buy(3, freeInk))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "AlreadyOwned", ink: freeInk },
    });
    expect(decide(rich, buy(4, rose, mallory))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "NotAMember", user: mallory },
    });
  });
});

describe("RoomService: the wallet", () => {
  it("charges a retried buy once, and lists the wallet oldest first", async () => {
    const store = memoryStore();
    const result = await Effect.runPromise(
      TestClock.setTime(start).pipe(
        Effect.andThen(
          RoomService.use((room) =>
            Effect.gen(function* () {
              yield* room.dispatch(RoomCommand.cases.Open.make({ pairId, members: [alice, bob] }));
              yield* room.saveCat(
                alice,
                {
                  name: catProfile.name,
                  look: catProfile.look,
                  utcOffsetSeconds: catProfile.utcOffsetSeconds,
                },
                catProfile.natureSeed,
              );
              for (let n = 1; n <= 5; n++) {
                yield* room.recordCatEvent(bob, {
                  id: uuid(n),
                  event: { _tag: "GamePlayed", game: yarn, score: 1, won: true },
                });
                yield* TestClock.adjust(Duration.minutes(1));
              }
              for (const n of [11, 12, 13, 14]) {
                yield* room.sendNote(
                  alice,
                  SendNoteRequest.cases.Text.make({ key: uuid(n), text: "hi", ink: freeInk }),
                );
              }
              const first = yield* room.buy(alice, uuid(20), rose);
              const retry = yield* room.buy(alice, uuid(20), rose);
              const page = yield* room.coinEntriesAfter(undefined, 2);
              const rest = yield* room.coinEntriesAfter(page.at(-1)?.id, 100);
              return { first, retry, page, rest, state: yield* room.state };
            }),
          ),
        ),
        Effect.provide(
          Layer.merge(
            RoomService.layer.pipe(Layer.provide(Layer.merge(store.layer, countingIds()))),
            TestClock.layer(),
          ),
        ),
      ),
    );
    expect(result.first).toMatchObject({ _tag: "Accepted" });
    expect(result.retry).toMatchObject({
      _tag: "Accepted",
      outputs: [{ _tag: "CoinsRepeated", entry: { id: `spend:${uuid(20)}`, amount: -60 } }],
    });
    // The welcome coins come first. Five wins hit the 40-coin cap after four, four notes add 20,
    // and a 60-coin ink takes those 60 back.
    expect(result.state._tag === "Active" && result.state.wallet.balance).toBe(560);
    expect(result.page.map((e) => e.amount)).toEqual([560, 10]);
    expect(result.rest.map((e) => e.amount)).toEqual([10, 10, 10, 5, 5, 5, 5, -60]);
  });
});
