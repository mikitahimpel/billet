import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  bundles,
  featuredSetAt,
  featuredSets,
  pieceSetOf,
  roomItemOf,
  roomItems,
  setPrice,
  ShopOffer,
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

  it("names only what the catalog sells", () => {
    expect(decode({ _tag: "Item", item: "lamp" })).toEqual({ _tag: "Item", item: "lamp" });
    expect(decode({ _tag: "Treat" })).toEqual({ _tag: "Treat" });
    for (const bad of [
      { _tag: "Item", item: "throne" },
      { _tag: "Set", set: "free-stuff" },
      { _tag: "Ink", ink: "ink-unknown" },
    ]) {
      expect(() => decode(bad), JSON.stringify(bad)).toThrow();
    }
  });
});
