import { Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { type CoinEntry, CoinEntryId } from "@billet/contracts-domain/coins";
import type { EpochMillis } from "@billet/contracts-domain/ids";
import { EconomyTap, economyChange, type EconomyObservation } from "../src/economy.ts";
import { RoomCommand } from "../src/room-command.ts";
import { RoomService } from "../src/room-service.ts";
import type { RoomWallet } from "../src/room-state.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import { alice, bob, pairId } from "./samples.ts";

const at: EpochMillis = 1_700_000_000_000;
const id = Schema.decodeSync(CoinEntryId);
const entry = (key: string, kind: CoinEntry["kind"], amount: number, ref = "x"): CoinEntry => ({
  id: id(key),
  kind,
  amount,
  ref,
  at,
});
const wallet = (over: Partial<RoomWallet> = {}): RoomWallet => ({
  balance: 0,
  care: 0,
  notes: 0,
  games: 0,
  lists: 0,
  ...over,
});
const change = (
  entries: ReadonlyArray<CoinEntry>,
  before: RoomWallet,
  after: RoomWallet,
): ReturnType<typeof economyChange> =>
  economyChange({ pairId, at, entries, before, after } satisfies EconomyObservation);

describe("economyChange", () => {
  it("reads a capped earn's source from how far the day's count rose", () => {
    const result = change(
      [entry("earn:a", "earn", 3)],
      wallet({ balance: 10, day: "2023-11-14" as never, care: 7 }),
      wallet({ balance: 13, day: "2023-11-14" as never, care: 10 }),
    );
    expect(result.totals).toEqual([{ source: "earn.care", credited: 3, debited: 0, entries: 1 }]);
    expect(result.capped).toEqual(["care"]);
    expect(result.balance).toBe(13);
    expect(result.day).toBe("2023-11-14");
  });

  it("starts the counts again on a new local day", () => {
    const result = change(
      [entry("earn:a", "earn", 2)],
      wallet({ day: "2023-11-13" as never, notes: 3 }),
      wallet({ balance: 2, day: "2023-11-14" as never, notes: 2 }),
    );
    expect(result.totals).toEqual([{ source: "earn.notes", credited: 2, debited: 0, entries: 1 }]);
    expect(result.capped).toEqual([]);
  });

  it("puts an earn that no cap counted under earn.other", () => {
    const result = change(
      [entry("earn:wish:w1", "earn", 20)],
      wallet({ day: "2023-11-14" as never }),
      wallet({ balance: 20, day: "2023-11-14" as never }),
    );
    expect(result.totals).toEqual([{ source: "earn.other", credited: 20, debited: 0, entries: 1 }]);
  });

  it("types every other entry by its kind, a refund and a spend as coins out", () => {
    const result = change(
      [
        entry("purchase:1", "purchase", 550, "pack"),
        entry("refund:1", "refund", -550, "pack"),
        entry("spend:1", "spend", -60, "ink-rose"),
        entry("gift:2023-11-14", "gift", 30),
        entry("bonus:c", "bonus", 150),
        entry("admin:s", "admin", 100),
        entry("buy:old", "buy", 100),
      ],
      wallet(),
      wallet({ balance: 250 }),
    );
    const by = Object.fromEntries(result.totals.map((t) => [t.source, [t.credited, t.debited]]));
    expect(by).toEqual({
      purchase: [650, 0],
      refund: [0, 550],
      spend: [0, 60],
      gift: [30, 0],
      bonus: [150, 0],
      admin: [100, 0],
    });
  });

  it("does not count a pair's kept coins moving to a new pair as bought", () => {
    const result = change([entry("purchase:kept-p", "purchase", 80, "kept")], wallet(), wallet());
    expect(result.totals).toEqual([{ source: "carried", credited: 80, debited: 0, entries: 1 }]);
  });
});

describe("RoomService tells the EconomyTap", () => {
  it("after a commit that enters coins, with the wallet before and after", async () => {
    const seen: EconomyObservation[] = [];
    const tap = Layer.succeed(EconomyTap, {
      observe: (observation) => Effect.sync(() => void seen.push(observation)),
    });
    await Effect.runPromise(
      TestClock.setTime(at).pipe(
        Effect.andThen(
          RoomService.use((room) =>
            room.dispatch(RoomCommand.cases.Open.make({ pairId, members: [alice, bob] })).pipe(
              Effect.andThen(
                room.creditPurchase({
                  kind: "purchase",
                  id: id("purchase:7"),
                  ref: "pack",
                  coins: 100,
                }),
              ),
            ),
          ),
        ),
        Effect.provide(
          Layer.mergeAll(
            RoomService.layer.pipe(
              Layer.provide(Layer.mergeAll(memoryStore().layer, countingIds(), tap)),
            ),
            TestClock.layer(),
          ),
        ),
      ),
    );
    const bought = seen.find(({ entries }) => entries.some((e) => e.id === "purchase:7"));
    expect(bought?.pairId).toBe(pairId);
    expect(bought?.before.balance).toBe(60);
    expect(bought?.after.balance).toBe(160);
  });
});
