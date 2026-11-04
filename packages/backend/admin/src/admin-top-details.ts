import type { ClientEventName } from "@billet/contracts-domain/metrics";
import { addDays } from "@billet/backend-metrics/funnel";

/** An `event_details` row, as the panel reads it. */
export interface DetailRow {
  readonly name: string;
  readonly detail: string;
  readonly day: string;
  readonly count: number;
  readonly total: number;
}

export interface TopDetail {
  readonly detail: string;
  readonly count: number;
  /** The sum of the values, a price in stamps. Only for names that carry one. */
  readonly total?: number;
}

/** The most chosen details of one name. */
export interface TopDetails {
  readonly name: ClientEventName;
  readonly items: ReadonlyArray<TopDetail>;
}

/** The names whose top details the panel shows, in this order. */
export const topNames: ReadonlyArray<ClientEventName> = [
  "CatChosen",
  "ShopItemBought",
  "ShopItemViewed",
  "RoomItemPlaced",
  "CatPlayed",
  "TrickDone",
  "TemperamentShown",
  "WidgetAdded",
];

const topCount = 5;

/**
 * The most chosen cats, items, toys and the like over the `days` ending `today`, at most
 * `topCount` per name, from `event_details`. Pure. Rows hold no person or pair.
 */
export const buildTopDetails = (
  details: ReadonlyArray<DetailRow>,
  today: string,
  days = 30,
): ReadonlyArray<TopDetails> => {
  const from = addDays(today, 1 - days);
  const tallies = new Map<string, Map<string, { count: number; total: number }>>();
  for (const row of details) {
    if (row.day < from || row.day > today) continue;
    const byDetail = tallies.get(row.name) ?? new Map<string, { count: number; total: number }>();
    const tally = byDetail.get(row.detail) ?? { count: 0, total: 0 };
    byDetail.set(row.detail, { count: tally.count + row.count, total: tally.total + row.total });
    tallies.set(row.name, byDetail);
  }
  return topNames.map((name) => ({
    name,
    items: [...(tallies.get(name) ?? new Map<string, { count: number; total: number }>())]
      .map(([detail, { count, total }]) =>
        name === "ShopItemBought" ? { detail, count, total } : { detail, count },
      )
      .toSorted((a, b) => b.count - a.count || a.detail.localeCompare(b.detail))
      .slice(0, topCount),
  }));
};
