import { addDays, type EventRow } from "@billet/backend-metrics/funnel";
import {
  ClientEventName,
  ServerEventName,
  type MetricEventName,
} from "@billet/contracts-domain/metrics";
import { buildTopDetails, type DetailRow, type TopDetails } from "./admin-top-details.ts";
import { buildHintRates, type HintRate } from "./admin-hint-rates.ts";
import { rangeOf, type OverviewRange } from "./admin-overview.ts";

export interface AppEvent {
  readonly name: MetricEventName;
  /** Sent by the app, or recorded by the server from what it already does. */
  readonly source: "app" | "server";
  /** Events in the range, and in the range just before it. */
  readonly total: number;
  readonly previousTotal: number;
  /** One count per day of the range, oldest first. */
  readonly daily: ReadonlyArray<number>;
  /** Pairs that had it at least once in the 7 days ending today. */
  readonly pairs7d: number;
  /** People who had it in the range. */
  readonly people: number;
  /** The first and the latest UTC day it was ever recorded; `null` if never. */
  readonly firstDay: string | null;
  readonly lastDay: string | null;
}

export interface AppEvents {
  readonly today: string;
  readonly range: { readonly days: OverviewRange; readonly from: string; readonly to: string };
  readonly days: ReadonlyArray<string>;
  /** Every event the contract knows, busiest first; ones never recorded come last. */
  readonly events: ReadonlyArray<AppEvent>;
  /** The most chosen cats, items and the like over the range: see `buildTopDetails`. */
  readonly top: ReadonlyArray<TopDetails>;
  /** Per hint, the pairs that saw it against the holdout: see `buildHintRates`. */
  readonly hints: ReadonlyArray<HintRate>;
}

const sources: ReadonlyArray<readonly [MetricEventName, AppEvent["source"]]> = [
  ...ClientEventName.literals.map((name) => [name, "app"] as const),
  ...ServerEventName.literals.map((name) => [name, "server"] as const),
];

/** Counts and days only: no ids leave it. */
export const buildAppEvents = (
  events: ReadonlyArray<EventRow>,
  today: string,
  days: number = 30,
  details: ReadonlyArray<DetailRow> = [],
): AppEvents => {
  const range = rangeOf(days);
  const dayList = Array.from({ length: range }, (_, index) => addDays(today, index - range + 1));
  const from = dayList[0] ?? today;
  const previousFrom = addDays(from, -range);
  const weekFrom = addDays(today, -6);
  const index = new Map(dayList.map((day, position) => [day, position]));

  const list = sources.map(([name, source]): AppEvent => {
    const daily = dayList.map(() => 0);
    const pairs = new Set<string>();
    const people = new Set<string>();
    let previousTotal = 0;
    let firstDay: string | null = null;
    let lastDay: string | null = null;
    for (const row of events) {
      if (row.name !== name) continue;
      if (firstDay === null || row.day < firstDay) firstDay = row.day;
      if (lastDay === null || row.day > lastDay) lastDay = row.day;
      const position = index.get(row.day);
      if (position !== undefined) {
        daily[position] = (daily[position] ?? 0) + row.count;
        people.add(row.userId);
      } else if (row.day >= previousFrom && row.day < from) previousTotal += row.count;
      if (row.pairId !== "" && row.day >= weekFrom && row.day <= today) pairs.add(row.pairId);
    }
    return {
      name,
      source,
      total: daily.reduce((a, b) => a + b, 0),
      previousTotal,
      daily,
      pairs7d: pairs.size,
      people: people.size,
      firstDay,
      lastDay,
    };
  });

  return {
    today,
    range: { days: range, from, to: today },
    days: dayList,
    events: list.toSorted(
      (a, b) =>
        Number(b.lastDay !== null) - Number(a.lastDay !== null) ||
        b.total - a.total ||
        a.name.localeCompare(b.name),
    ),
    top: buildTopDetails(details, today, range),
    hints: buildHintRates(details, today, range),
  };
};
