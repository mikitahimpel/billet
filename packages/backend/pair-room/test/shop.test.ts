import { Effect, Layer, Schema } from "effect";
import { describe, expect, it } from "vitest";
import type { EpochMillis } from "@billet/contracts-domain/ids";
import { RoomItemId, type ShopOffer } from "@billet/contracts-domain/shop";
import { decide } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import type { RoomDecision } from "../src/room-decision.ts";
import { RoomService } from "../src/room-service.ts";
import type { ActiveRoom } from "../src/room-state.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import { active, alice, bob, mallory, rose, tower, uuid } from "./samples.ts";

// Monday 2024-01-08 12:00 UTC: week 1, so "nap-time" is the featured set.
const monday: EpochMillis = Date.UTC(2024, 0, 8, 12);
const day = 86_400_000;
const piece = Schema.decodeUnknownSync(RoomItemId);

const rich: ActiveRoom = { ...active, wallet: { ...active.wallet, balance: 2000 } };

const order = (n: number, offer: ShopOffer, at = monday, by = alice) =>
  RoomCommand.cases.Order.make({ id: uuid(n), by, offer, at });

const accept = (room: ActiveRoom, command: RoomCommand): RoomDecision & { _tag: "Accepted" } => {
  const decision = decide(room, command);
  if (decision._tag !== "Accepted") throw new Error(`rejected: ${decision.rejection._tag}`);
  return decision;
};

const rejection = (room: ActiveRoom, command: RoomCommand) => {
  const decision = decide(room, command);
  return decision._tag === "Rejected" ? decision.rejection : undefined;
};

describe("ordering a piece", () => {
  it("charges the catalog price and gives the piece to the pair", () => {
    const decision = accept(rich, order(1, { _tag: "Item", item: tower }));
    expect(decision.state.items).toEqual([tower]);
    expect(decision.state.wallet.balance).toBe(2000 - 540);
    expect(decision.outputs).toEqual([
      {
        _tag: "CoinsEntered",
        entry: { id: `spend:${uuid(1)}`, kind: "spend", amount: -540, ref: "tower", at: monday },
      },
      { _tag: "ItemsGranted", items: [tower] },
    ]);
  });

  it("refuses a piece the pair has, a starter included", () => {
    const owned = accept(rich, order(1, { _tag: "Item", item: tower })).state;
    expect(rejection(owned, order(2, { _tag: "Item", item: tower }))).toEqual({
      _tag: "OfferOwned",
      offer: "tower",
    });
    expect(rejection(rich, order(3, { _tag: "Item", item: piece("lamp") }))?._tag).toBe(
      "OfferOwned",
    );
  });

  it("refuses an order the balance cannot pay, and a stranger's", () => {
    expect(rejection(active, order(1, { _tag: "Item", item: tower }))).toEqual({
      _tag: "NotEnoughCoins",
      needed: 540,
      have: 0,
    });
    expect(rejection(rich, order(2, { _tag: "Treat" }, monday, mallory))?._tag).toBe("NotAMember");
  });

  it("takes a bought piece off the wishlist", () => {
    const wished = accept(
      rich,
      RoomCommand.cases.SetWish.make({ by: bob, item: tower, wished: true }),
    );
    const bought = accept(wished.state, order(1, { _tag: "Item", item: tower }));
    expect(bought.state.wishlist).toEqual([]);
    expect(bought.outputs.at(-1)).toEqual({ _tag: "WishlistChanged", wishlist: [] });
  });
});

describe("ordering a set", () => {
  it("charges its share of the missing pieces and gives only those", () => {
    // Reading nook: bookcase 260 and armchair 320; the lamp is a starter. 580 at 0.75 is 435.
    const decision = accept(rich, order(1, { _tag: "Set", set: "reading-nook" as never }));
    expect(decision.state.items).toEqual([piece("bookcase"), piece("armchair")]);
    expect(decision.state.wallet.balance).toBe(2000 - 435);
  });

  it("sells a featured set only in its week, wherever the couple is", () => {
    const nap = { _tag: "Set", set: "nap-time" } as ShopOffer;
    expect(decide(rich, order(1, nap))._tag).toBe("Accepted");
    // Sunday 23:00 UTC is already Monday east of UTC.
    expect(decide(rich, order(2, nap, Date.UTC(2024, 0, 7, 23)))._tag).toBe("Accepted");
    expect(rejection(rich, order(3, nap, monday + 7 * day))?._tag).toBe("NotOffered");
  });

  it("refuses a set the pair owns all of", () => {
    const nook = { _tag: "Set", set: "reading-nook" } as ShopOffer;
    const owned = accept(rich, order(1, nook)).state;
    expect(rejection(owned, order(2, nook))).toEqual({ _tag: "OfferOwned", offer: "reading-nook" });
  });
});

describe("ordering an ink or a treat", () => {
  it("buys an ink like Buy does", () => {
    const decision = accept(rich, order(1, { _tag: "Ink", ink: rose }));
    expect(decision.state.inks).toEqual([rose]);
    expect(decision.outputs).toContainEqual({ _tag: "InksGranted", inks: [rose] });
  });

  it("spends a treat's price and gives nothing to keep", () => {
    const decision = accept(rich, order(1, { _tag: "Treat" }));
    expect(decision.state.wallet.balance).toBe(1990);
    expect(decision.state.items).toEqual([]);
    expect(decision.outputs).toHaveLength(1);
  });
});

describe("wishing", () => {
  const wish = (item: RoomItemId, wished: boolean, by = alice) =>
    RoomCommand.cases.SetWish.make({ by, item, wished });

  it("adds and removes a piece, in order, once", () => {
    const yarn = piece("yarn");
    const both = [wish(tower, true), wish(yarn, true), wish(tower, true)].reduce(
      (room, command) => accept(room, command).state,
      active,
    );
    expect(both.wishlist).toEqual([tower, yarn]);
    expect(accept(both, wish(tower, true)).outputs).toEqual([]);
    expect(accept(both, wish(tower, false)).state.wishlist).toEqual([yarn]);
  });

  it("refuses a piece the catalog does not sell, and a stranger", () => {
    expect(rejection(active, wish(piece("throne"), true))?._tag).toBe("NotOffered");
    expect(rejection(active, wish(tower, true, mallory))?._tag).toBe("NotAMember");
  });
});

describe("RoomService.order", () => {
  it("answers a retried id with the first spend and charges once", async () => {
    const store = memoryStore();
    store.memory.state = rich;
    const outcome = await Effect.runPromise(
      RoomService.use((room) =>
        Effect.gen(function* () {
          const first = yield* room.order(alice, uuid(1), { _tag: "Item", item: tower });
          const again = yield* room.order(alice, uuid(1), { _tag: "Item", item: tower });
          return { first, again, state: yield* room.state };
        }),
      ).pipe(
        Effect.provide(
          RoomService.layer.pipe(Layer.provide(Layer.merge(store.layer, countingIds()))),
        ),
      ),
    );
    expect(outcome.first._tag).toBe("Accepted");
    expect(outcome.again).toMatchObject({
      _tag: "Accepted",
      outputs: [{ _tag: "CoinsRepeated", entry: { id: `spend:${uuid(1)}`, amount: -540 } }],
    });
    expect(outcome.state._tag === "Active" && outcome.state.wallet.balance).toBe(2000 - 540);
    expect(store.memory.coins.map((entry) => entry.amount)).toEqual([-540]);
  });
});
