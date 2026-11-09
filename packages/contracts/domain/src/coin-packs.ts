import { Schema } from "effect";

/** Canonical: the app's `coin-packs.json` and StoreKit configuration must match (tested in
 * `contracts-fixtures`). Prices: US tier in USD. Placeholders until the owner sets them. */
export const coinPacks = [
  { id: "com.mikitahimpel.billet.coins.100", coins: 100, price: "0.99" },
  { id: "com.mikitahimpel.billet.coins.550", coins: 550, price: "4.99" },
  { id: "com.mikitahimpel.billet.coins.1200", coins: 1200, price: "9.99" },
] as const;

export type CoinPack = (typeof coinPacks)[number];

export const CoinPackId = Schema.Literals([coinPacks[0].id, coinPacks[1].id, coinPacks[2].id]);
export type CoinPackId = typeof CoinPackId.Type;

export const coinPackOf = (productId: string): CoinPack | undefined =>
  coinPacks.find(({ id }) => id === productId);

/** Every App Store transaction for billet names it. */
export const appBundleId = "com.mikitahimpel.billet";
