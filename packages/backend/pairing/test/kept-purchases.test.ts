import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import { mergeKept, splitKept } from "../src/kept-purchases.ts";

const user = Schema.decodeSync(UserId);
const [ana, ben] = [user("user-a"), user("user-b")];
const shop = { coins: 101, inks: ["ink-rose"], items: ["lantern"] };

describe("splitKept", () => {
  it("gives each partner a copy of the inks and pieces and half of the coins", () => {
    expect(splitKept([ben, ana], shop)).toEqual([
      [ana, { coins: 51, inks: ["ink-rose"], items: ["lantern"] }],
      [ben, { coins: 50, inks: ["ink-rose"], items: ["lantern"] }],
    ]);
  });

  it("splits an even balance evenly, and never loses or invents a coin", () => {
    for (const coins of [0, 1, 2, 99, 100]) {
      const parts = splitKept([ana, ben], { ...shop, coins });
      expect(parts.reduce((sum, [, kept]) => sum + kept.coins, 0)).toBe(coins);
      expect(Math.abs((parts[0]?.[1].coins ?? 0) - (parts[1]?.[1].coins ?? 0))).toBeLessThanOrEqual(
        1,
      );
    }
  });

  it("gives one keeper everything, and nobody nothing", () => {
    expect(splitKept([ana], shop)).toEqual([[ana, shop]]);
    expect(splitKept([], shop)).toEqual([]);
  });
});

describe("mergeKept", () => {
  it("adds coins and takes each ink and piece once", () => {
    expect(
      mergeKept([
        { coins: 51, inks: ["ink-rose"], items: ["lantern"] },
        { coins: 50, inks: ["ink-rose", "ink-sky"], items: [] },
      ]),
    ).toEqual({ coins: 101, inks: ["ink-rose", "ink-sky"], items: ["lantern"] });
  });
});
