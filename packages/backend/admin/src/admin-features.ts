import type { ClientEventName } from "@billet/contracts-domain/metrics";
import { addDays, type EventRow, type FlagRow, wilson } from "@billet/backend-metrics/funnel";
import { minimumGroup } from "./admin-retention.ts";

/** "Of pairs" means pairs active in that window, so one that left long ago doesn't count. */

export type FeatureArea = "cat" | "room" | "shop" | "streak" | "widget";

export const featureAreas: ReadonlyArray<{
  readonly area: FeatureArea;
  readonly label: string;
  readonly events: ReadonlyArray<ClientEventName>;
}> = [
  {
    area: "cat",
    label: "Cat",
    events: ["CatPetted", "CatFed", "CatPlayed", "CatCalled", "TrickDone"],
  },
  {
    area: "room",
    label: "Room",
    events: [
      "DecoratingOpened",
      "RoomItemPlaced",
      "RoomItemMoved",
      "RoomItemPutAway",
      "RoomCustomised",
    ],
  },
  {
    area: "shop",
    label: "Shop",
    events: [
      "ShopOpened",
      "ShopItemViewed",
      "ShopItemBought",
      "ShopOfferViewed",
      "ShopBundleBought",
      "ShopDailyGiftClaimed",
      "ShopGiftSent",
    ],
  },
  { area: "streak", label: "Streak", events: ["StreakOpened", "StreakMilestoneSeen"] },
  { area: "widget", label: "Widget", events: ["WidgetAdded", "WidgetButtonTapped"] },
];

export const featureWindows = [7, 30] as const;
export type FeatureWindow = (typeof featureWindows)[number];

/** Pairs that used it, of the active ones; null when either is under `minimumGroup`. */
export interface UsageShare {
  readonly count: number;
  readonly of: number;
  readonly share: number;
  readonly low: number;
  readonly high: number;
}

export interface UsageCell {
  readonly d7: UsageShare | null;
  readonly d30: UsageShare | null;
}

export interface FeatureRow {
  readonly area: FeatureArea;
  /** The event, or null for the area's "any of these" row. */
  readonly event: ClientEventName | null;
  /** One per group, in the order of `groups`. */
  readonly cells: ReadonlyArray<UsageCell>;
}

export interface FeatureGroup {
  /** The variant, or null for every pair. */
  readonly variant: string | null;
  /** Active pairs in each window; null when under `minimumGroup`. */
  readonly active: { readonly d7: number | null; readonly d30: number | null };
}

export interface FeatureUsage {
  readonly today: string;
  /** The first day of each window. */
  readonly from: { readonly d7: string; readonly d30: string };
  readonly split: string | null;
  /** Everyone first, then each variant of `split` by name. */
  readonly groups: ReadonlyArray<FeatureGroup>;
  readonly areas: ReadonlyArray<{ readonly area: FeatureArea; readonly label: string }>;
  readonly rows: ReadonlyArray<FeatureRow>;
  /** Experiment keys present in `pair_flags`, for the split picker. */
  readonly experiments: ReadonlyArray<string>;
}

const usage = (count: number, of: number): UsageShare | null => {
  if (count < minimumGroup || of < minimumGroup) return null;
  const interval = wilson(count, of);
  return { count, of, share: count / of, low: interval?.low ?? 0, high: interval?.high ?? 1 };
};

interface Window {
  /** Pairs with any row in the window. */
  readonly active: Set<string>;
  /** Event name to the pairs that had it in the window. */
  readonly byEvent: Map<string, Set<string>>;
}

const windowOf = (
  events: ReadonlyArray<EventRow>,
  from: string,
  today: string,
  pairs: ReadonlySet<string> | null,
): Window => {
  const active = new Set<string>();
  const byEvent = new Map<string, Set<string>>();
  for (const row of events) {
    if (row.pairId === "" || row.day < from || row.day > today) continue;
    if (pairs !== null && !pairs.has(row.pairId)) continue;
    active.add(row.pairId);
    const set = byEvent.get(row.name) ?? new Set<string>();
    set.add(row.pairId);
    byEvent.set(row.name, set);
  }
  return { active, byEvent };
};

const pairsUsing = (window: Window, names: ReadonlyArray<string>) => {
  const used = new Set<string>();
  for (const name of names) for (const pair of window.byEvent.get(name) ?? []) used.add(pair);
  return used.size;
};

export const buildFeatureUsage = (
  events: ReadonlyArray<EventRow>,
  flags: ReadonlyArray<FlagRow>,
  today: string,
  options: { readonly split?: string | undefined } = {},
): FeatureUsage => {
  const from = { d7: addDays(today, -6), d30: addDays(today, -29) };
  const split = options.split;
  const members: Array<[string | null, ReadonlySet<string> | null]> = [[null, null]];
  if (split !== undefined) {
    const byVariant = new Map<string, Set<string>>();
    for (const flag of flags) {
      if (flag.experimentKey !== split) continue;
      const set = byVariant.get(flag.variant) ?? new Set<string>();
      set.add(flag.pairId);
      byVariant.set(flag.variant, set);
    }
    for (const variant of [...byVariant.keys()].toSorted()) {
      members.push([variant, byVariant.get(variant) ?? null]);
    }
  }
  const windows = members.map(([variant, pairs]) => ({
    variant,
    d7: windowOf(events, from.d7, today, pairs),
    d30: windowOf(events, from.d30, today, pairs),
  }));
  const cellFor = (names: ReadonlyArray<string>) =>
    windows.map((group): UsageCell => ({
      d7: usage(pairsUsing(group.d7, names), group.d7.active.size),
      d30: usage(pairsUsing(group.d30, names), group.d30.active.size),
    }));
  const atLeast = (count: number) => (count < minimumGroup ? null : count);

  return {
    today,
    from,
    split: split ?? null,
    groups: windows.map(({ variant, d7, d30 }) => ({
      variant,
      active: { d7: atLeast(d7.active.size), d30: atLeast(d30.active.size) },
    })),
    areas: featureAreas.map(({ area, label }) => ({ area, label })),
    rows: featureAreas.flatMap(({ area, events: names }) => [
      { area, event: null, cells: cellFor(names) },
      ...names.map((event) => ({ area, event, cells: cellFor([event]) })),
    ]),
    experiments: [...new Set(flags.map(({ experimentKey }) => experimentKey))].toSorted(),
  };
};
