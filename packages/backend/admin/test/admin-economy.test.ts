import { describe, expect, it } from "vitest";
import {
  buildEconomyReport,
  percentile,
  tooFew,
  type EconomyDayRow,
  type EconomyPairDayRow,
} from "../src/admin-economy.ts";

const today = "2026-11-13";

const pairDay = (
  pairId: string,
  day: string,
  over: Partial<EconomyPairDayRow> = {},
): EconomyPairDayRow => ({
  pairId,
  day,
  earned: 0,
  balance: 0,
  lastAt: 1,
  cappedCare: 0,
  cappedNotes: 0,
  cappedGames: 0,
  cappedLists: 0,
  ...over,
});

const row = (
  day: string,
  source: string,
  credited: number,
  debited = 0,
  entries = 1,
): EconomyDayRow => ({ day, source, credited, debited, entries });

const report = (
  days: ReadonlyArray<EconomyDayRow>,
  pairDays: ReadonlyArray<EconomyPairDayRow>,
  extra: { range?: number; holdDays?: number } = {},
) => buildEconomyReport({ days, pairDays, today, range: extra.range ?? 7, ...extra });

describe("percentile", () => {
  it("is the nearest rank", () => {
    expect(percentile([], 0.5)).toBeNull();
    expect(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.5)).toBe(5);
    expect(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.9)).toBe(9);
    expect(percentile([7], 0.9)).toBe(7);
  });
});

describe("coins by day and source", () => {
  const result = report(
    [
      row("2026-11-12", "earn.care", 10, 0, 10),
      row("2026-11-12", "earn.other", 20),
      row("2026-11-12", "purchase", 550),
      row("2026-11-12", "carried", 80),
      row("2026-11-12", "spend", 0, 60),
      row("2026-11-12", "refund", 0, 550),
      row("2026-11-13", "earn.care", 5, 0, 5),
      row("2026-11-01", "earn.care", 999),
    ],
    [],
  );

  it("mints everything that came in but carried coins, and spends only what the shop took", () => {
    const day = result.days.find((d) => d.day === "2026-11-12");
    expect(day).toMatchObject({ minted: 580, spent: 60, refunded: 550 });
    expect(day?.bySource.map((s) => s.source)).toEqual([
      "earn.care",
      "earn.other",
      "purchase",
      "refund",
      "carried",
      "spend",
    ]);
  });

  it("totals the range only, with a row for every day, empty ones too", () => {
    expect(result.days.map((d) => d.day)).toEqual([
      "2026-11-07",
      "2026-11-08",
      "2026-11-09",
      "2026-11-10",
      "2026-11-11",
      "2026-11-12",
      "2026-11-13",
    ]);
    expect(result.totals).toMatchObject({ minted: 585, spent: 60, refunded: 550 });
    expect(result.totals.bySource.find((s) => s.source === "earn.care")).toMatchObject({
      credited: 15,
      entries: 15,
    });
  });
});

describe("balance spread", () => {
  const many = (balances: ReadonlyArray<number>, day = today) =>
    balances.map((balance, i) => pairDay(`p${i}`, day, { balance, earned: 10 }));

  it("gives the median, p90 and the pairs in debt over each pair's latest balance", () => {
    const result = report([], many([-40, 0, 10, 20, 30, 40, 50, 60, 70, 100]));
    expect(result.balance).toEqual({ pairs: 10, median: 30, p90: 70, negative: 1 });
    expect(result.days.at(-1)?.balance).toEqual({ pairs: 10, median: 30, p90: 70, negative: 1 });
  });

  it("leaves the figures out under the minimum number of pairs", () => {
    const result = report([], many([1, 2, 3, 4]));
    expect(tooFew).toBe(5);
    expect(result.balance).toEqual({ pairs: 4, median: null, p90: null, negative: null });
    expect(result.hoarding).toMatchObject({ pairs: 4, share: null, typicalDailyEarn: null });
    expect(result.capHitRate).toEqual({ care: null, notes: null, games: null, lists: null });
  });

  it("takes a pair's latest day and, within a day, its latest write", () => {
    const rows = [
      ...many([5, 5, 5, 5], "2026-11-10"),
      pairDay("p0", "2026-11-12", { balance: 100, earned: 10 }),
      pairDay("p4", "2026-11-13", { balance: 7, earned: 10, lastAt: 9 }),
      pairDay("p4", "2026-11-13", { balance: 3, earned: 10, lastAt: 2 }),
    ];
    const result = report([], rows);
    expect(result.balance.pairs).toBe(5);
    expect(result.balance.median).toBe(5);
  });
});

describe("hoarding", () => {
  it("is the share of pairs holding more than N typical days of earnings", () => {
    const rows = [
      // Each earns 10 a day, so 14 days is 140 coins: b, c and e hold more.
      pairDay("a", "2026-11-12", { earned: 10, balance: 50 }),
      pairDay("b", "2026-11-12", { earned: 10, balance: 200 }),
      pairDay("c", "2026-11-12", { earned: 10, balance: 2000 }),
      pairDay("d", "2026-11-12", { earned: 10, balance: 100 }),
      pairDay("e", "2026-11-12", { earned: 10, balance: 150 }),
      // Never earned in the range: not measured.
      pairDay("f", "2026-11-12", { earned: 0, balance: 99999 }),
    ];
    const result = report([], rows, { holdDays: 14 });
    expect(result.hoarding).toEqual({
      holdDays: 14,
      pairs: 5,
      share: 3 / 5,
      typicalDailyEarn: 10,
    });
    expect(report([], rows, { holdDays: 30 }).hoarding.share).toBe(1 / 5);
  });

  it("uses the mean over the days a pair earned on", () => {
    const rows = ["a", "b", "c", "d", "e"].flatMap((id) => [
      pairDay(id, "2026-11-11", { earned: 10, balance: 0 }),
      pairDay(id, "2026-11-12", { earned: 30, balance: 300 }),
    ]);
    // 20 a day typically: 300 is 15 days of it.
    expect(report([], rows, { holdDays: 14 }).hoarding).toMatchObject({
      share: 1,
      typicalDailyEarn: 20,
    });
    expect(report([], rows, { holdDays: 16 }).hoarding.share).toBe(0);
  });
});

describe("daily-cap hit rate", () => {
  it("is the share of the pairs that earned who reached each cap", () => {
    const rows = [
      pairDay("a", today, { earned: 10, cappedCare: 1, cappedGames: 1 }),
      pairDay("b", today, { earned: 10, cappedCare: 1 }),
      pairDay("c", today, { earned: 10 }),
      pairDay("d", today, { earned: 10 }),
      pairDay("e", today, { earned: 10 }),
      pairDay("f", today, { earned: 0, balance: -5 }),
    ];
    const result = report([], rows);
    expect(result.days.at(-1)?.capHitRate).toEqual({
      care: 2 / 5,
      notes: 0,
      games: 1 / 5,
      lists: 0,
    });
    expect(result.capHitRate.care).toBe(2 / 5);
    expect(result.caps).toMatchObject({ care: 2, notes: 3, games: 4, lists: 1 });
  });
});
