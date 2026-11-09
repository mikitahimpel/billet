import { Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { CoinEntryId } from "@billet/contracts-domain/coins";
import type { EpochMillis } from "@billet/contracts-domain/ids";
import { decide } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import type { RoomDecision } from "../src/room-decision.ts";
import { RoomService } from "../src/room-service.ts";
import type { ActiveRoom } from "../src/room-state.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import { active, alice, bob, pairId, rose, uuid, vacant, welcomed } from "./samples.ts";

const start: EpochMillis = 1_700_000_000_000;
const entryId = Schema.decodeSync(CoinEntryId);
const pack = "com.ourio.app.coins.550";

const credit = (kind: "buy" | "refund", coins: number, id = `purchase:${kind}-1`) =>
  RoomCommand.cases.CreditPurchase.make({ id: entryId(id), kind, coins, ref: pack, at: start });

const accept = (room: ActiveRoom, command: RoomCommand): RoomDecision & { _tag: "Accepted" } => {
  const decision = decide(room, command);
  if (decision._tag !== "Accepted") throw new Error(`rejected: ${decision.rejection._tag}`);
  return decision;
};

describe("coins bought with money", () => {
  it("pays a pack into the wallet under the payments ledger's id", () => {
    const decision = accept(active, credit("buy", 550, "purchase:2000"));
    expect(decision.state.wallet.balance).toBe(550);
    expect(decision.outputs).toEqual([
      {
        _tag: "CoinsEntered",
        entry: { id: "purchase:2000", kind: "buy", amount: 550, ref: pack, at: start },
      },
    ]);
  });

  it("takes a refunded pack back", () => {
    const decision = accept(welcomed, credit("refund", 550, "refund:2000"));
    expect(decision.state.wallet.balance).toBe(10);
    expect(decision.outputs).toEqual([
      {
        _tag: "CoinsEntered",
        entry: { id: "refund:2000", kind: "refund", amount: -550, ref: pack, at: start },
      },
    ]);
  });

  it("never takes a refund below 0, and records what it took", () => {
    const poorer = { ...active, wallet: { ...active.wallet, balance: 30 } };
    const decision = accept(poorer, credit("refund", 550, "refund:2000"));
    expect(decision.state.wallet.balance).toBe(0);
    expect(decision.outputs).toMatchObject([{ entry: { amount: -30 } }]);
    const empty = accept(active, credit("refund", 550, "refund:2001"));
    expect(empty.outputs).toMatchObject([{ entry: { amount: 0 } }]);
    expect(Object.is(empty.state.wallet.balance, 0)).toBe(true);
  });

  it("needs an open room", () => {
    expect(decide(vacant, credit("buy", 550))).toMatchObject({
      _tag: "Rejected",
      rejection: { _tag: "RoomNotOpen" },
    });
  });
});

describe("RoomService: coins bought with money", () => {
  const run = <A>(body: (room: RoomService["Service"]) => Effect.Effect<A>) =>
    Effect.runPromise(
      TestClock.setTime(start).pipe(
        Effect.andThen(
          RoomService.use((room) =>
            room
              .dispatch(RoomCommand.cases.Open.make({ pairId, members: [alice, bob] }))
              .pipe(Effect.andThen(body(room))),
          ),
        ),
        Effect.provide(
          Layer.merge(
            RoomService.layer.pipe(Layer.provide(Layer.merge(memoryStore().layer, countingIds()))),
            TestClock.layer(),
          ),
        ),
      ),
    );

  const purchase = entryId("purchase:2000");
  const refund = entryId("refund:2000");
  const restore = entryId("restore:2000");

  it("credits a pack once: a repeat answers with the first entry", async () => {
    const result = await run((room) =>
      Effect.gen(function* () {
        yield* room.creditPurchase({ kind: "buy", id: purchase, ref: pack, coins: 550 });
        const repeat = yield* room.creditPurchase({
          kind: "buy",
          id: purchase,
          ref: pack,
          coins: 550,
        });
        return { repeat, entries: yield* room.coinEntriesAfter(undefined, 10) };
      }),
    );
    expect(result.repeat).toMatchObject({
      _tag: "Accepted",
      outputs: [{ _tag: "CoinsRepeated", entry: { id: purchase, amount: 550 } }],
      state: { wallet: { balance: 1110 } },
    });
    expect(result.entries.map(({ id, amount }) => [id, amount])).toEqual([
      ["gift:welcome", 560],
      [purchase, 550],
    ]);
  });

  it("refunds what the credit paid, once", async () => {
    const result = await run((room) =>
      Effect.gen(function* () {
        yield* room.creditPurchase({ kind: "buy", id: purchase, ref: pack, coins: 550 });
        yield* room.buy(alice, uuid(1), rose);
        const state = yield* room.state;
        const before = state._tag === "Active" ? state.wallet.balance : undefined;
        const first = yield* room.creditPurchase({
          kind: "refund",
          id: refund,
          ref: pack,
          reverses: purchase,
        });
        const repeat = yield* room.creditPurchase({
          kind: "refund",
          id: refund,
          ref: pack,
          reverses: purchase,
        });
        return { before, first, repeat };
      }),
    );
    expect(result.before).toBe(1050);
    expect(result.first).toMatchObject({
      outputs: [{ _tag: "CoinsEntered", entry: { id: refund, kind: "refund", amount: -550 } }],
      state: { wallet: { balance: 500 } },
    });
    expect(result.repeat).toMatchObject({
      outputs: [{ _tag: "CoinsRepeated", entry: { id: refund, amount: -550 } }],
      state: { wallet: { balance: 500 } },
    });
  });

  it("restores only what the refund took, and refunds nothing the room never credited", async () => {
    const result = await run((room) =>
      Effect.gen(function* () {
        yield* room.creditPurchase({ kind: "buy", id: purchase, ref: pack, coins: 1000 });
        yield* room.creditPurchase({ kind: "refund", id: refund, ref: pack, reverses: purchase });
        const restored = yield* room.creditPurchase({
          kind: "buy",
          id: restore,
          ref: pack,
          reverses: refund,
        });
        const unknown = yield* room.creditPurchase({
          kind: "refund",
          id: entryId("refund:3000"),
          ref: pack,
          reverses: entryId("purchase:3000"),
        });
        return { restored, unknown };
      }),
    );
    // The welcome 560 plus 1000 is 1560, all of which the refund could take back.
    expect(result.restored).toMatchObject({
      outputs: [{ entry: { id: restore, kind: "buy", amount: 1000 } }],
      state: { wallet: { balance: 1560 } },
    });
    expect(result.unknown).toMatchObject({
      outputs: [{ entry: { amount: 0 } }],
      state: { wallet: { balance: 1560 } },
    });
  });
});
