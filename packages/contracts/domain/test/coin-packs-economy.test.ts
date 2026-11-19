import { describe, expect, it } from "vitest";
import { coinPacks } from "@billet/contracts-domain/coin-packs";
import { inks } from "@billet/contracts-domain/inks";
import { postage } from "@billet/contracts-domain/postage";
import {
  bundles,
  dealPool,
  featuredSets,
  roomItems,
  starterItems,
} from "@billet/contracts-domain/shop";

// Packs only shorten the wait (docs/economy.md): the biggest one must never own the whole shop.
const biggestPack = Math.max(...coinPacks.map(({ coins }) => coins));
const forSale = roomItems.filter(({ id }) => !starterItems.includes(id));

// The deepest cut anywhere in the shop: a daily deal, a bundle or the week's featured set.
const deepestDiscount = Math.max(
  ...dealPool.map(({ discount }) => discount),
  ...[...bundles, ...featuredSets].map(({ share }) => 1 - share),
);

const pieces = forSale.reduce((sum, { price }) => sum + price, 0);
const paidInks = inks.reduce((sum, { price }) => sum + price, 0);
const stampsAndSeals = postage.reduce((sum, { price }) => sum + price, 0);
const everything = pieces + paidInks + stampsAndSeals;
// No path is cheaper than every piece at the deepest discount; inks and postage are never cut.
const floor = pieces * (1 - deepestDiscount) + paidInks + stampsAndSeals;

describe("the biggest coin pack cannot buy the whole shop", () => {
  it("costs well under everything at list price", () => {
    expect(everything).toBe(3000);
    expect(everything).toBeGreaterThanOrEqual(2 * biggestPack);
  });

  it("stays under everything even if every piece were bought at the deepest discount", () => {
    expect(deepestDiscount).toBe(0.5);
    expect(floor).toBeGreaterThanOrEqual(1.5 * biggestPack);
  });
});
