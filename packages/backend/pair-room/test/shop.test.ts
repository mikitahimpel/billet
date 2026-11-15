import { Effect, Layer, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { type EpochMillis, NoteId } from "@billet/contracts-domain/ids";
import { freeInk } from "@billet/contracts-domain/inks";
import { Note } from "@billet/contracts-domain/note";
import { postage, sealPrice, stampPrice } from "@billet/contracts-domain/postage";
import { RoomItemId, type ShopOffer } from "@billet/contracts-domain/shop";
import { decide } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import type { RoomDecision } from "../src/room-decision.ts";
import { RoomService } from "../src/room-service.ts";
import type { ActiveRoom } from "../src/room-state.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import { active, adoptedCat, alice, bob, mallory, rose, textFrom, tower, uuid } from "./samples.ts";

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
      { _tag: "Purchased", id: uuid(1), by: alice, at: monday, items: [tower], coins: 540 },
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
    expect(bought.outputs).toContainEqual({ _tag: "WishlistChanged", wishlist: [] });
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
    const decision = accept({ ...rich, cat: adoptedCat }, order(1, { _tag: "Treat" }));
    expect(decision.state.wallet.balance).toBe(1990);
    expect(decision.state.items).toEqual([]);
    expect(decision.outputs.map((output) => output._tag)).toEqual([
      "CoinsEntered",
      "CatEntryAppended",
      "Purchased",
    ]);
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

describe("unlocking a stamp or a seal", () => {
  const stamped = (stamp: "moon", seal?: "rose"): Note =>
    Note.cases.Text.make({
      id: Schema.decodeUnknownSync(NoteId)("note-stamped"),
      author: alice,
      sentAt: 1_700_000_000_000,
      text: "hi",
      ink: freeInk,
      stamp,
      ...(seal === undefined ? {} : { seal }),
    });
  const send = (room: ActiveRoom, note: Note, n = 50) =>
    decide(room, RoomCommand.cases.SendNote.make({ note, key: uuid(n) }));

  it("charges every stamp 30 and every seal 45, and nothing is free", () => {
    for (const entry of postage) {
      const decision = accept(rich, order(1, { _tag: "Postage", postage: entry.id }));
      expect(decision.state.postage).toEqual([entry.id]);
      expect(decision.state.wallet.balance).toBe(
        2000 - (entry.id.startsWith("stamp-") ? stampPrice : sealPrice),
      );
    }
    expect(postage).toHaveLength(10);
  });

  it("grants the unlock to the pair and tells the shop and the Inbox", () => {
    const decision = accept(rich, order(1, { _tag: "Postage", postage: "seal-rose" }));
    expect(decision.outputs).toEqual([
      {
        _tag: "CoinsEntered",
        entry: { id: `spend:${uuid(1)}`, kind: "spend", amount: -45, ref: "seal-rose", at: monday },
      },
      { _tag: "PostageGranted", postage: ["seal-rose"] },
      { _tag: "Purchased", id: uuid(1), by: alice, at: monday, items: ["seal-rose"], coins: 45 },
    ]);
  });

  it("refuses one the pair has, one the balance cannot pay, a raised price and a stranger", () => {
    const owned = accept(rich, order(1, { _tag: "Postage", postage: "stamp-moon" })).state;
    expect(
      rejection(owned, order(2, { _tag: "Postage", postage: "stamp-moon" }, monday, bob)),
    ).toEqual({ _tag: "OfferOwned", offer: "stamp-moon" });
    expect(rejection(active, order(3, { _tag: "Postage", postage: "seal-plum" }))).toEqual({
      _tag: "NotEnoughCoins",
      needed: 45,
      have: 0,
    });
    const capped = RoomCommand.cases.Order.make({
      id: uuid(4),
      by: alice,
      offer: { _tag: "Postage", postage: "seal-plum" },
      at: monday,
      terms: { expectedPrice: 30 },
    });
    expect(rejection(rich, capped)).toEqual({ _tag: "PriceChanged", price: 45 });
    expect(
      rejection(rich, order(5, { _tag: "Postage", postage: "stamp-sun" }, monday, mallory))?._tag,
    ).toBe("NotAMember");
  });

  it("refuses a note whose stamp or seal is locked, and sends it once both are the pair's", () => {
    expect(send(active, textFrom(alice, freeInk))._tag).toBe("Accepted");
    const refused = send(active, stamped("moon", "rose"));
    expect(refused).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "PostageNotOwned", postage: "stamp-moon" },
    });
    const withStamp = accept(rich, order(1, { _tag: "Postage", postage: "stamp-moon" })).state;
    expect(send(withStamp, stamped("moon", "rose"))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "PostageNotOwned", postage: "seal-rose" },
    });
    expect(send(withStamp, stamped("moon"))._tag).toBe("Accepted");
    const both = accept(withStamp, order(2, { _tag: "Postage", postage: "seal-rose" })).state;
    expect(send(both, { ...stamped("moon", "rose"), author: bob })._tag).toBe("Accepted");
  });

  it("gives back kept stamps and seals once, in the order they come", () => {
    const grant = (room: ActiveRoom, ids: ReadonlyArray<"stamp-moon" | "seal-rose">) =>
      decide(room, RoomCommand.cases.GrantPostage.make({ postage: ids }));
    const first = grant(active, ["seal-rose", "stamp-moon", "seal-rose"]);
    if (first._tag !== "Accepted") throw new Error("rejected");
    expect(first.state.postage).toEqual(["seal-rose", "stamp-moon"]);
    expect(first.outputs).toEqual([
      { _tag: "PostageGranted", postage: ["seal-rose", "stamp-moon"] },
    ]);
    expect(grant(first.state, ["stamp-moon"])).toEqual({
      _tag: "Accepted",
      state: first.state,
      outputs: [],
    });
  });
});
