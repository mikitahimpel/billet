import { describe, expect, it } from "vitest";
import { dailyEarnCaps, rewardFor, rewardForEarn } from "@billet/contracts-domain/coins";
import { inks } from "@billet/contracts-domain/inks";
import { collections, giftCoins, roomItems, welcomeCoins } from "@billet/contracts-domain/shop";
import { streakDayCoins } from "@billet/contracts-domain/streak";

// What a pair can earn on a fully active day: every daily cap, the daily gift at its best, and a
// lit streak day. One-off earns (a wish, a rated date) are rare and are not a daily pace.
const maxPerDay =
  Object.values(dailyEarnCaps).reduce((sum, cap) => sum + cap, 0) +
  Math.max(...giftCoins) +
  streakDayCoins;

const prices = [...roomItems.map(({ price }) => price), ...inks.map(({ price }) => price)]
  .filter((price) => price > 0)
  .toSorted((a, b) => a - b);
const cheapest = prices[0] ?? 0;
const top = prices.at(-2) ?? 0;

describe("coins are slow to earn against the shop's prices", () => {
  it("a fully active day earns at most about 13 coins", () => {
    expect(maxPerDay).toBeLessThanOrEqual(14);
  });

  it("the cheapest paid item takes at least 3 days of full play", () => {
    expect(cheapest / maxPerDay).toBeGreaterThanOrEqual(3);
  });

  it("the top items take at least 4 weeks of full play", () => {
    expect(top / maxPerDay).toBeGreaterThanOrEqual(28);
  });

  it("the welcome coins buy one cheap piece at most, never a big one", () => {
    expect(welcomeCoins).toBeLessThan(2 * cheapest);
    expect(welcomeCoins).toBeLessThan(top / 4);
  });

  it("a collection bonus is a fraction of a day's play, not a shortcut", () => {
    for (const { bonus } of collections) expect(bonus).toBeLessThanOrEqual(4 * maxPerDay);
  });

  it("no single reward is more than a few days' play toward the cheapest item", () => {
    const cats = [
      rewardFor({ _tag: "NoteShared", kind: "Photo" } as never)?.coins ?? 0,
      rewardForEarn({ _tag: "DateRated", plan: "p" as never }).coins,
      rewardForEarn({ _tag: "WishReceived", wish: "w" as never }).coins,
    ];
    for (const coins of cats) expect(coins).toBeLessThan(cheapest / 4);
  });
});
