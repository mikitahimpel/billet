import { describe, expect, it } from "vitest";
import type { ShopCatalogItem } from "@billet/contracts-domain/shop-catalog";
import { priceBookOf } from "../src/price-book.ts";
import { seedItems } from "../src/shop-seed.ts";

const lamp = seedItems.find((item) => item.id === "lamp") as ShopCatalogItem;
const withSale: ShopCatalogItem = { ...lamp, sale: { price: 100, from: 1_000, until: 2_000 } };

describe("the price book", () => {
  it("takes the sale price only inside the sale's window", () => {
    const priceAt = (at: number) =>
      priceBookOf([withSale], at).items.find((entry) => entry.id === "lamp")?.price;
    expect(priceAt(999)).toBe(140);
    expect(priceAt(1_000)).toBe(100);
    expect(priceAt(1_999)).toBe(100);
    expect(priceAt(2_000)).toBe(140);
  });

  it("keeps inks apart from pieces", () => {
    const book = priceBookOf(seedItems, 0);
    expect(book.inks.map((ink) => ink.id)).toContain("ink-rose");
    expect(book.items.map((item) => item.id)).not.toContain("ink-rose");
  });

  it("orders the deals by their draw order, not their shelf order", () => {
    const first = { ...lamp, deal: { discount: 0.5, order: 2 } };
    const second = { ...(seedItems[1] as ShopCatalogItem), deal: { discount: 0.1, order: 1 } };
    expect(priceBookOf([first, second], 0).deals.map((deal) => deal.item)).toEqual([
      second.id,
      first.id,
    ]);
  });
});
