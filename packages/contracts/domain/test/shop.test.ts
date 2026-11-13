import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { LocalDay } from "@billet/contracts-domain/coins";
import {
  bundles,
  collections,
  dealCount,
  dealsOn,
  featuredSetAt,
  featuredSets,
  fnv1a,
  giftItems,
  giftCoins,
  giftOn,
  itemPriceOn,
  pieceSetOf,
  roomItemOf,
  roomItems,
  setPrice,
  ShopOffer,
  splitMix64,
  starterItems,
} from "@billet/contracts-domain/shop";

describe("room items", () => {
  it("have unique ids, a price each, and starters the catalog sells", () => {
    expect(new Set(roomItems.map(({ id }) => id)).size).toBe(roomItems.length);
    for (const { price } of roomItems) expect(price).toBeGreaterThan(0);
    for (const id of starterItems) expect(roomItemOf(id)).toBeDefined();
  });

  it("sets name only pieces the catalog sells, under unique ids", () => {
    const sets = [...bundles, ...featuredSets];
    expect(new Set(sets.map(({ id }) => id)).size).toBe(sets.length);
    for (const { items } of sets) for (const id of items) expect(roomItemOf(id)).toBeDefined();
  });
});

describe("featured set", () => {
  const monday = Date.UTC(2024, 0, 1);
  const day = 86_400_000;

  it("changes on Mondays, in turn", () => {
    expect(featuredSetAt(monday).id).toBe("rainy-evening");
    expect(featuredSetAt(monday + 6 * day + day - 1).id).toBe("rainy-evening");
    expect(featuredSetAt(monday + 7 * day).id).toBe("nap-time");
    expect(featuredSetAt(monday + 21 * day).id).toBe("rainy-evening");
  });

  it("follows the couple's midnight", () => {
    const sundayEvening = monday + 7 * day - 3_600_000;
    expect(featuredSetAt(sundayEvening).id).toBe("rainy-evening");
    expect(featuredSetAt(sundayEvening, 2 * 3600).id).toBe("nap-time");
  });
});

describe("set price", () => {
  const nook = pieceSetOf("reading-nook");

  it("is the share of the missing pieces, rounded to 5", () => {
    expect(nook).toBeDefined();
    if (nook === undefined) return;
    // 260 + 320 + 140 = 720, at 0.75 = 540.
    expect(setPrice(nook, new Set())).toEqual({ price: 540, sum: 720 });
    // 260 + 320 = 580, at 0.75 = 435.
    expect(setPrice(nook, new Set(["lamp"]))).toEqual({ price: 435, sum: 580 });
    expect(setPrice(nook, new Set(["lamp", "armchair", "bookcase"]))).toBeUndefined();
  });
});

describe("offer", () => {
  const decode = Schema.decodeUnknownSync(ShopOffer);

  // Items and inks come from the admin's catalog, so any well-formed id decodes and the room
  // refuses one it does not sell; sets are still the app's own.
  it("takes any well-formed item or ink and only the known sets", () => {
    expect(decode({ _tag: "Item", item: "lamp" })).toEqual({ _tag: "Item", item: "lamp" });
    expect(decode({ _tag: "Item", item: "throne" })).toEqual({ _tag: "Item", item: "throne" });
    expect(decode({ _tag: "Ink", ink: "ink-unknown" })).toEqual({
      _tag: "Ink",
      ink: "ink-unknown",
    });
    expect(decode({ _tag: "Treat" })).toEqual({ _tag: "Treat" });
    for (const bad of [
      { _tag: "Item", item: "Throne!" },
      { _tag: "Set", set: "free-stuff" },
      { _tag: "Ink", ink: "unknown" },
    ]) {
      expect(() => decode(bad), JSON.stringify(bad)).toThrow();
    }
  });
});

describe("collections", () => {
  it("name only pieces the catalog sells, under unique ids", () => {
    expect(new Set(collections.map(({ id }) => id)).size).toBe(collections.length);
    for (const { items } of collections)
      for (const id of items) expect(roomItemOf(id)).toBeDefined();
  });
});

describe("the seeded rotations", () => {
  const localDay = Schema.decodeSync(LocalDay);

  it("hash with FNV-1a and draw with SplitMix64, as the app does", () => {
    expect(fnv1a("")).toBe(0xcbf2_9ce4_8422_2325n);
    expect(fnv1a("a")).toBe(0xaf63_dc4c_8601_ec8cn);
    expect(splitMix64(0n)()).toBe(0xe220_a839_7b1d_cdafn);
  });

  it("draw four different deals, the same for the same pair and day", () => {
    const deals = dealsOn("pair-1", localDay("2026-11-05"));
    expect(deals).toHaveLength(dealCount);
    expect(new Set(deals.map((deal) => deal.item)).size).toBe(dealCount);
    expect(dealsOn("pair-1", localDay("2026-11-05"))).toEqual(deals);
    expect(dealsOn("pair-2", localDay("2026-11-05"))).not.toEqual(deals);
  });

  it("price a piece at its deal on the day it is one", () => {
    const today = localDay("2026-11-05");
    for (const deal of dealsOn("pair-1", today)) {
      const piece = roomItemOf(deal.item);
      if (piece === undefined) throw new Error(deal.item);
      expect(itemPriceOn(piece, "pair-1", today)).toEqual({ price: deal.price, deal });
      expect(deal.price).toBeLessThan(piece.price);
    }
    const armchair = roomItemOf("armchair");
    if (armchair === undefined) throw new Error("no armchair");
    expect(itemPriceOn(armchair, "pair-1", today)).toEqual({ price: 320 });
  });

  it("give an owned gift piece as coins instead", () => {
    const owned = new Set<string>(giftItems);
    for (let date = 1; date <= 28; date++) {
      const day = localDay(`2026-02-${String(date).padStart(2, "0")}`);
      expect(giftOn("pair-1", day, owned)._tag).toBe("Coins");
    }
  });

  it("never pay a gift of 0 coins: a gift is at least a coin or a piece", () => {
    expect(Math.min(...giftCoins)).toBeGreaterThanOrEqual(1);
    for (let date = 1; date <= 28; date++) {
      const day = localDay(`2026-02-${String(date).padStart(2, "0")}`);
      const gift = giftOn("pair-1", day, new Set());
      if (gift._tag === "Coins") expect(gift.coins).toBeGreaterThanOrEqual(1);
    }
  });
});
