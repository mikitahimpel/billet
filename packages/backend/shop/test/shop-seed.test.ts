import { describe, expect, it } from "vitest";
import { inks } from "@billet/contracts-domain/inks";
import { dealPool, roomItems } from "@billet/contracts-domain/shop";
import { dealsOn } from "@billet/contracts-domain/shop";
import { priceBookOf } from "../src/price-book.ts";
import { seedItems } from "../src/shop-seed.ts";

describe("the seed", () => {
  it("has every piece and every sold ink of the canonical lists at their prices", () => {
    const prices = new Map(seedItems.map((item) => [item.id, item.price]));
    for (const piece of roomItems) expect(prices.get(piece.id), piece.id).toBe(piece.price);
    for (const ink of inks.filter((entry) => entry.price > 0)) {
      expect(prices.get(ink.id), ink.id).toBe(ink.price);
    }
    expect(prices.has("ink-graphite")).toBe(false);
    expect(seedItems).toHaveLength(roomItems.length + inks.length - 1);
  });

  it("makes the same book as the canonical lists, so a deploy changes no price and no deal", () => {
    const book = priceBookOf(seedItems, 0);
    expect(book.items).toEqual(roomItems.map(({ id, price }) => ({ id, price })));
    expect(book.deals).toEqual(dealPool.map(({ item, discount }) => ({ item, discount })));
    for (const day of ["2026-11-07", "2026-11-08", "2027-01-01"] as const) {
      for (const seed of ["pair-a", "pair-b"]) {
        expect(dealsOn(seed, day as never, book)).toEqual(dealsOn(seed, day as never));
      }
    }
  });
});
