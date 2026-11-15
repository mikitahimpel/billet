import { describe, expect, it } from "vitest";
import { dailyEarnCaps } from "@billet/contracts-domain/coins";
import { inks } from "@billet/contracts-domain/inks";
import { roomItems } from "@billet/contracts-domain/shop";
import {
  streakDayCoins,
  streakMilestoneCoins,
  streakMilestones,
  streakRewardCoins,
} from "@billet/contracts-domain/streak";

const paidPrices = [...roomItems.map(({ price }) => price), ...inks.map(({ price }) => price)]
  .filter((price) => price > 0)
  .toSorted((a, b) => a - b);
const cheapest = paidPrices[0] ?? 0;
const median = paidPrices[Math.floor(paidPrices.length / 2)] ?? 0;

describe("streak coins stay small against the shop", () => {
  it("pays milestones only at milestones", () => {
    for (const days of Object.keys(streakMilestoneCoins).map(Number)) {
      expect(streakMilestones).toContain(days);
    }
    expect(streakRewardCoins(2)).toBe(streakDayCoins);
    expect(streakRewardCoins(7)).toBe(streakDayCoins + (streakMilestoneCoins[7] ?? 0));
  });

  it("a full week of lit days earns under a third of the cheapest paid piece", () => {
    const week = Array.from({ length: 7 }, (_, index) => streakRewardCoins(index + 1));
    expect(week.reduce((sum, coins) => sum + coins, 0) * 3).toBeLessThan(cheapest);
  });

  it("a milestone is a small fraction of a mid-priced piece", () => {
    for (const coins of Object.values(streakMilestoneCoins)) {
      expect(coins * 6).toBeLessThanOrEqual(median);
    }
  });

  it("a lit day is a tenth of a day of play at most, and a year of them stays near the top piece's price", () => {
    const careDay = Object.values(dailyEarnCaps).reduce((sum, cap) => sum + cap, 0);
    expect(streakDayCoins * 10).toBeLessThanOrEqual(careDay);
    const year = Array.from({ length: 365 }, (_, index) => streakRewardCoins(index + 1));
    expect(year.reduce((sum, coins) => sum + coins, 0)).toBeLessThan(500);
  });
});
