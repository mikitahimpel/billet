import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import type { EpochMillis } from "@billet/contracts-domain/ids";
import { PieceSetId, RoomItemId, type ShopOffer } from "@billet/contracts-domain/shop";
import type { PriceBook, PriceTerms } from "@billet/contracts-domain/shop-catalog";
import { decide } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import type { RoomDecision } from "../src/room-decision.ts";
import type { ActiveRoom } from "../src/room-state.ts";
import { active, alice, rose, tower, uuid } from "./samples.ts";

const monday: EpochMillis = Date.UTC(2024, 0, 8, 12);
const piece = Schema.decodeUnknownSync(RoomItemId);
const rich: ActiveRoom = { ...active, wallet: { ...active.wallet, balance: 2000 } };

// The tower costs 600 here, not the canonical 540; the yarn is gone; "moon" is new; the rose is 80.
const book: PriceBook = {
  items: [
    { id: "tower", price: 600 },
    { id: "moon", price: 200 },
  ],
  inks: [{ id: "ink-rose", price: 80 }],
  deals: [],
};

const order = (offer: ShopOffer, terms?: PriceTerms) =>
  RoomCommand.cases.Order.make({
    id: uuid(1),
    by: alice,
    offer,
    at: monday,
    ...(terms === undefined ? {} : { terms }),
  });

const result = (command: RoomCommand): RoomDecision => decide(rich, command);

describe("pricing from the catalog's book", () => {
  it("charges the book's price, not the canonical one", () => {
    const decision = result(order({ _tag: "Item", item: tower }, { book }));
    expect(decision._tag === "Accepted" && decision.state.wallet.balance).toBe(2000 - 600);
  });

  it("sells a piece only the book knows, and refuses one the book dropped", () => {
    const moon = result(order({ _tag: "Item", item: piece("moon") }, { book }));
    expect(moon._tag).toBe("Accepted");
    const yarn = result(order({ _tag: "Item", item: piece("yarn") }, { book }));
    expect(yarn).toMatchObject({ _tag: "Rejected", rejection: { _tag: "NotOffered" } });
  });

  it("prices an ink from the book and refuses one it dropped", () => {
    const bought = result(order({ _tag: "Ink", ink: rose }, { book }));
    expect(bought._tag === "Accepted" && bought.state.wallet.balance).toBe(2000 - 80);
    const none = result(order({ _tag: "Ink", ink: rose }, { book: { ...book, inks: [] } }));
    expect(none).toMatchObject({ _tag: "Rejected", rejection: { _tag: "NotSold" } });
  });

  it("sells a set only while every piece in it is on sale", () => {
    const set = result(
      order({ _tag: "Set", set: Schema.decodeSync(PieceSetId)("mochi-playday") }, { book }),
    );
    expect(set).toMatchObject({ _tag: "Rejected", rejection: { _tag: "NotOffered" } });
  });
});

describe("the price the buyer saw", () => {
  it("refuses an order whose price rose, with the new price, and charges nothing", () => {
    const decision = result(order({ _tag: "Item", item: tower }, { book, expectedPrice: 540 }));
    expect(decision).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "PriceChanged", price: 600 },
    });
  });

  it("charges the lower price when it fell", () => {
    const decision = result(order({ _tag: "Item", item: tower }, { book, expectedPrice: 700 }));
    expect(decision._tag === "Accepted" && decision.state.wallet.balance).toBe(2000 - 600);
  });

  it("accepts the price the buyer saw", () => {
    const decision = result(order({ _tag: "Item", item: tower }, { book, expectedPrice: 600 }));
    expect(decision._tag).toBe("Accepted");
  });

  it("holds for an ink bought with Buy too", () => {
    const decision = result(
      RoomCommand.cases.Buy.make({
        id: uuid(2),
        by: alice,
        ink: rose,
        at: monday,
        terms: { book, expectedPrice: 60 },
      }),
    );
    expect(decision).toMatchObject({
      _tag: "Rejected",
      rejection: { _tag: "PriceChanged", price: 80 },
    });
  });
});

describe("deals from the book", () => {
  it("draw from the book's pool at the book's prices", () => {
    const dealBook: PriceBook = {
      items: [{ id: "moon", price: 200 }],
      inks: [],
      deals: [{ item: "moon", discount: 0.25 }],
    };
    const decision = result(order({ _tag: "Item", item: piece("moon") }, { book: dealBook }));
    // One item in the pool, so it is every day's deal: 200 less 25%.
    expect(decision._tag === "Accepted" && decision.state.wallet.balance).toBe(2000 - 150);
  });
});
