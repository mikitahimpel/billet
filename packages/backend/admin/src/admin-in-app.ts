import { ClientEventName } from "@billet/contracts-domain/metrics";
import { addDays, type EventRow } from "@billet/backend-metrics/funnel";

/** An `event_details` row, as the panel reads it. */
export interface DetailRow {
  readonly name: string;
  readonly detail: string;
  readonly day: string;
  readonly count: number;
  readonly total: number;
}

export interface InAppEvent {
  readonly name: ClientEventName;
  /** One count per day, oldest first, for the days of `InApp.days`. */
  readonly daily: ReadonlyArray<number>;
  /** Pairs with at least one of it in the 7 days ending today. Unpaired people are not counted. */
  readonly pairs7d: number;
}

export interface TopDetail {
  readonly detail: string;
  readonly count: number;
  /** The sum of the values, a price in stamps. Only for names that carry one. */
  readonly total?: number;
}

export interface InApp {
  /** The days of every `daily` list, oldest first. */
  readonly days: ReadonlyArray<string>;
  readonly events: ReadonlyArray<InAppEvent>;
  /** The most chosen details in the last 30 days, per name, at most `topCount` each. */
  readonly top: ReadonlyArray<{
    readonly name: ClientEventName;
    readonly items: ReadonlyArray<TopDetail>;
  }>;
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
 * The Overview's "In the app" block: what people do in the app, from the D1 counts. Pure. Days are
 * UTC days; `today` is the last one shown.
 */
export const buildInApp = (
  events: ReadonlyArray<EventRow>,
  details: ReadonlyArray<DetailRow>,
  today: string,
  days = 14,
): InApp => {
  const shown = Array.from({ length: days }, (_, index) => addDays(today, index - days + 1));
  const weekStart = addDays(today, -6);
  const monthStart = addDays(today, -29);

  const counts = new Map<string, Map<string, number>>();
  const pairs = new Map<string, Set<string>>();
  for (const row of events) {
    const byDay = counts.get(row.name) ?? new Map<string, number>();
    byDay.set(row.day, (byDay.get(row.day) ?? 0) + row.count);
    counts.set(row.name, byDay);
    if (row.pairId !== "" && row.day >= weekStart && row.day <= today) {
      const seen = pairs.get(row.name) ?? new Set<string>();
      seen.add(row.pairId);
      pairs.set(row.name, seen);
    }
  }

  const tallies = new Map<string, Map<string, { count: number; total: number }>>();
  for (const row of details) {
    if (row.day < monthStart || row.day > today) continue;
    const byDetail = tallies.get(row.name) ?? new Map<string, { count: number; total: number }>();
    const tally = byDetail.get(row.detail) ?? { count: 0, total: 0 };
    byDetail.set(row.detail, { count: tally.count + row.count, total: tally.total + row.total });
    tallies.set(row.name, byDetail);
  }

  return {
    days: shown,
    events: ClientEventName.literals.map((name) => ({
      name,
      daily: shown.map((day) => counts.get(name)?.get(day) ?? 0),
      pairs7d: pairs.get(name)?.size ?? 0,
    })),
    top: topNames.map((name) => ({
      name,
      items: [...(tallies.get(name) ?? new Map<string, { count: number; total: number }>())]
        .map(([detail, { count, total }]) =>
          name === "ShopItemBought" ? { detail, count, total } : { detail, count },
        )
        .toSorted((a, b) => b.count - a.count || a.detail.localeCompare(b.detail))
        .slice(0, topCount),
    })),
  };
};
