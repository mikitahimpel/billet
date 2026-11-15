import { Context, type Effect } from "effect";
import { type CoinEntry, type EarnSource, dailyEarnCaps } from "@billet/contracts-domain/coins";
import type { EpochMillis } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { RoomWallet } from "./room-state.ts";

/**
 * Where coins entered or left a wallet, for tuning. `earn.*` are the faucets: the four daily-capped
 * ones, and `earn.other` for the once-per-ref earns that have no cap. `carried` is a pair's kept
 * coins moving to a new pair: no coin is minted by it.
 */
export const economySources = [
  "earn.care",
  "earn.notes",
  "earn.games",
  "earn.lists",
  "earn.other",
  "purchase",
  "refund",
  "gift",
  "bonus",
  "admin",
  "carried",
  "spend",
] as const;
export type EconomySource = (typeof economySources)[number];

export const cappedSources: ReadonlyArray<EarnSource> = ["care", "notes", "games", "lists"];

export interface EconomyObservation {
  readonly pairId: PairId;
  readonly at: EpochMillis;
  readonly entries: ReadonlyArray<CoinEntry>;
  readonly before: RoomWallet;
  readonly after: RoomWallet;
}

export interface SourceTotal {
  readonly source: EconomySource;
  /** Coins that came in (positive amounts), however many entries. */
  readonly credited: number;
  /** Coins that went out, as a positive number. */
  readonly debited: number;
  readonly entries: number;
}

export interface EconomyChange {
  /** UTC day of the observation, `YYYY-MM-DD`. */
  readonly day: string;
  readonly totals: ReadonlyArray<SourceTotal>;
  /** Coins earned in play by the whole change, against any cap. */
  readonly earned: number;
  /** The wallet's balance after the change. */
  readonly balance: number;
  /** The daily-capped sources whose cap the pair has now reached on its current local day. */
  readonly capped: ReadonlyArray<EarnSource>;
}

const entrySource = (entry: CoinEntry): Exclude<EconomySource, `earn.${string}`> | "earn" => {
  switch (entry.kind) {
    case "earn":
      return "earn";
    case "purchase":
    case "buy":
      return entry.ref === "kept" ? "carried" : "purchase";
    case "refund":
    case "gift":
    case "bonus":
    case "admin":
    case "spend":
      return entry.kind;
  }
};

/** Counts the wallet holds for `day`, zero for a day it has not counted yet. */
const countsOf = (wallet: RoomWallet, day: string | undefined) =>
  wallet.day === day || (wallet.day !== undefined && day === undefined)
    ? wallet
    : { care: 0, notes: 0, games: 0, lists: 0 };

/**
 * What one committed decision moved, by source. A capped earn's source is read from how far the
 * wallet's daily counts rose, because the entry itself only says it was an earn.
 */
export const economyChange = (observation: EconomyObservation): EconomyChange => {
  const { before, after, entries, at } = observation;
  const totals = new Map<EconomySource, { credited: number; debited: number; entries: number }>();
  const add = (source: EconomySource, amount: number) => {
    const total = totals.get(source) ?? { credited: 0, debited: 0, entries: 0 };
    totals.set(source, {
      credited: total.credited + Math.max(0, amount),
      debited: total.debited + Math.max(0, -amount),
      entries: total.entries + 1,
    });
  };
  let earned = 0;
  let earnEntries = 0;
  for (const entry of entries) {
    const source = entrySource(entry);
    if (source === "earn") {
      earned += entry.amount;
      earnEntries += 1;
    } else {
      add(source, entry.amount);
    }
  }
  if (earnEntries > 0) {
    const base = countsOf(before, after.day);
    let attributed = 0;
    for (const source of cappedSources) {
      const rose = Math.max(0, after[source] - base[source]);
      const coins = Math.min(rose, earned - attributed);
      if (coins > 0) {
        add(`earn.${source}`, coins);
        attributed += coins;
      }
    }
    if (earned - attributed > 0) add("earn.other", earned - attributed);
  }
  return {
    day: new Date(at).toISOString().slice(0, 10),
    totals: [...totals].map(([source, total]) => ({ source, ...total })),
    earned,
    balance: after.balance,
    capped: cappedSources.filter(
      (source) => after.day !== undefined && after[source] >= dailyEarnCaps[source],
    ),
  };
};

/**
 * Told after each committed decision that entered coins. It only measures: a failure is the
 * implementation's to swallow, and the room never waits on it.
 */
export class EconomyTap extends Context.Service<
  EconomyTap,
  { readonly observe: (observation: EconomyObservation) => Effect.Effect<void> }
>()("@billet/backend-pair-room/EconomyTap") {}
