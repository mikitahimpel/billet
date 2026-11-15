import { Schema } from "effect";
import { dailyEarnCaps, type EarnSource } from "@billet/contracts-domain/coins";
import { addDays } from "@billet/backend-metrics/funnel";
import {
  cappedSources,
  economySources,
  type EconomySource,
} from "@billet/backend-pair-room/economy";

const Day = Schema.String.check(Schema.isPattern(/^\d{4}-\d{2}-\d{2}$/));

/** What each stored table holds. A test in `platform` fails if a table's columns differ. */
export const EconomyDayRow = Schema.Struct({
  day: Day,
  source: Schema.String,
  credited: Schema.Int,
  debited: Schema.Int,
  entries: Schema.Int,
});
export type EconomyDayRow = typeof EconomyDayRow.Type;

export const EconomyPairDayRow = Schema.Struct({
  pairId: Schema.String,
  day: Day,
  earned: Schema.Int,
  balance: Schema.Int,
  lastAt: Schema.Int,
  cappedCare: Schema.Int,
  cappedNotes: Schema.Int,
  cappedGames: Schema.Int,
  cappedLists: Schema.Int,
});
export type EconomyPairDayRow = typeof EconomyPairDayRow.Type;

/** Below this many pairs a figure is left out, as everywhere in the panel. */
export const tooFew = 5;

export const economyRanges = [7, 30, 90] as const;
export const defaultHoldDays = 14;

export interface SourceFigures {
  readonly source: EconomySource;
  readonly credited: number;
  readonly debited: number;
  readonly entries: number;
}

export interface BalanceSpread {
  readonly pairs: number;
  /** Null under `tooFew` pairs. */
  readonly median: number | null;
  readonly p90: number | null;
  /** Pairs whose balance is below 0: a refund took back coins they had spent. */
  readonly negative: number | null;
}

export interface EconomyDay {
  readonly day: string;
  /** Coins that came in, every source but `carried`: earned, bought, given. */
  readonly minted: number;
  /** Coins the shop took. */
  readonly spent: number;
  /** Coins Apple refunds took back. */
  readonly refunded: number;
  readonly bySource: ReadonlyArray<SourceFigures>;
  /** Pairs that moved coins that day. */
  readonly pairs: number;
  readonly balance: BalanceSpread;
  /** Per capped source, the share of the pairs that earned that day who reached its cap. */
  readonly capHitRate: Readonly<Record<EarnSource, number | null>>;
}

export interface EconomyReport {
  readonly range: number;
  readonly from: string;
  readonly to: string;
  readonly days: ReadonlyArray<EconomyDay>;
  /** Over the whole range. */
  readonly totals: {
    readonly minted: number;
    readonly spent: number;
    readonly refunded: number;
    readonly bySource: ReadonlyArray<SourceFigures>;
  };
  /** Each pair's balance after its last coin change in the range. */
  readonly balance: BalanceSpread;
  /**
   * A pair's typical day is its mean coins earned per day it earned any in the range; it holds
   * more than `holdDays` days when its balance is over `holdDays` of that.
   */
  readonly hoarding: {
    readonly holdDays: number;
    readonly pairs: number;
    readonly share: number | null;
    readonly typicalDailyEarn: number | null;
  };
  readonly capHitRate: Readonly<Record<EarnSource, number | null>>;
  readonly caps: Readonly<Record<EarnSource, number>>;
  readonly tooFew: number;
}

/** Nearest rank: the smallest value with at least `p` of the values at or below it. */
export const percentile = (sorted: ReadonlyArray<number>, p: number): number | null => {
  if (sorted.length === 0) return null;
  const rank = Math.max(1, Math.ceil(p * sorted.length));
  return sorted[rank - 1] ?? null;
};

const spread = (balances: ReadonlyArray<number>): BalanceSpread => {
  if (balances.length < tooFew) {
    return { pairs: balances.length, median: null, p90: null, negative: null };
  }
  const sorted = balances.toSorted((a, b) => a - b);
  return {
    pairs: balances.length,
    median: percentile(sorted, 0.5),
    p90: percentile(sorted, 0.9),
    negative: balances.filter((balance) => balance < 0).length,
  };
};

const cappedOf = (row: EconomyPairDayRow, source: EarnSource): boolean =>
  (source === "care"
    ? row.cappedCare
    : source === "notes"
      ? row.cappedNotes
      : source === "games"
        ? row.cappedGames
        : row.cappedLists) === 1;

const hitRates = (rows: ReadonlyArray<EconomyPairDayRow>) => {
  const earners = rows.filter((row) => row.earned > 0);
  return Object.fromEntries(
    cappedSources.map((source) => [
      source,
      earners.length < tooFew
        ? null
        : earners.filter((row) => cappedOf(row, source)).length / earners.length,
    ]),
  ) as Record<EarnSource, number | null>;
};

const figuresOf = (rows: ReadonlyArray<EconomyDayRow>): ReadonlyArray<SourceFigures> =>
  economySources.flatMap((source) => {
    const mine = rows.filter((row) => row.source === source);
    if (mine.length === 0) return [];
    return [
      {
        source,
        credited: mine.reduce((sum, row) => sum + row.credited, 0),
        debited: mine.reduce((sum, row) => sum + row.debited, 0),
        entries: mine.reduce((sum, row) => sum + row.entries, 0),
      },
    ];
  });

const totalsOf = (figures: ReadonlyArray<SourceFigures>) => ({
  minted: figures.reduce((sum, f) => (f.source === "carried" ? sum : sum + f.credited), 0),
  spent: figures.find((f) => f.source === "spend")?.debited ?? 0,
  refunded: figures.find((f) => f.source === "refund")?.debited ?? 0,
});

/**
 * Pair-level aggregates only: the rows carry a pair id and numbers, never a person, a note or a
 * coin entry's reference.
 */
export const buildEconomyReport = (input: {
  readonly days: ReadonlyArray<EconomyDayRow>;
  readonly pairDays: ReadonlyArray<EconomyPairDayRow>;
  readonly today: string;
  readonly range: number;
  readonly holdDays?: number;
}): EconomyReport => {
  const { today, range } = input;
  const holdDays = input.holdDays ?? defaultHoldDays;
  const from = addDays(today, -(range - 1));
  const inRange = (day: string) => day >= from && day <= today;
  const dayRows = input.days.filter((row) => inRange(row.day));
  const pairRows = input.pairDays.filter((row) => inRange(row.day));

  const days = Array.from({ length: range }, (_, i) => addDays(from, i)).map((day): EconomyDay => {
    const bySource = figuresOf(dayRows.filter((row) => row.day === day));
    const pairsThatDay = pairRows.filter((row) => row.day === day);
    return {
      day,
      ...totalsOf(bySource),
      bySource,
      pairs: pairsThatDay.length,
      balance: spread(pairsThatDay.map((row) => row.balance)),
      capHitRate: hitRates(pairsThatDay),
    };
  });

  const latest = new Map<string, EconomyPairDayRow>();
  for (const row of pairRows) {
    const known = latest.get(row.pairId);
    if (
      known === undefined ||
      row.day > known.day ||
      (row.day === known.day && row.lastAt > known.lastAt)
    ) {
      latest.set(row.pairId, row);
    }
  }
  const earnedBy = new Map<string, { coins: number; days: number }>();
  for (const row of pairRows) {
    if (row.earned <= 0) continue;
    const known = earnedBy.get(row.pairId) ?? { coins: 0, days: 0 };
    earnedBy.set(row.pairId, { coins: known.coins + row.earned, days: known.days + 1 });
  }
  const measured = [...earnedBy].map(([pairId, { coins, days: n }]) => ({
    typical: coins / n,
    balance: latest.get(pairId)?.balance ?? 0,
  }));
  const typical = measured.map((pair) => pair.typical).toSorted((a, b) => a - b);

  const totals = figuresOf(dayRows);
  return {
    range,
    from,
    to: today,
    days,
    totals: { ...totalsOf(totals), bySource: totals },
    balance: spread([...latest.values()].map((row) => row.balance)),
    hoarding: {
      holdDays,
      pairs: measured.length,
      share:
        measured.length < tooFew
          ? null
          : measured.filter((pair) => pair.balance > holdDays * pair.typical).length /
            measured.length,
      typicalDailyEarn: measured.length < tooFew ? null : percentile(typical, 0.5),
    },
    capHitRate: hitRates(pairRows.filter((row) => row.earned > 0)),
    caps: dailyEarnCaps,
    tooFew,
  };
};
