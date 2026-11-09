import { Schema } from "effect";

/** Canonical: the app's `coin-packs.json` and StoreKit configuration must match (tested in
 * `contracts-fixtures`). Prices: US tier in USD. Placeholders until the owner sets them. */
export const coinPacks = [
  { id: "com.ourio.app.coins.100", coins: 100, price: "0.99" },
  { id: "com.ourio.app.coins.550", coins: 550, price: "4.99" },
  { id: "com.ourio.app.coins.1200", coins: 1200, price: "9.99" },
] as const;

export type CoinPack = (typeof coinPacks)[number];

export const CoinPackId = Schema.Literals([coinPacks[0].id, coinPacks[1].id, coinPacks[2].id]);
export type CoinPackId = typeof CoinPackId.Type;

/** Every App Store transaction for the app names it. */
export const appBundleId = "com.ourio.app";

/** The first App Store app's bundle. TestFlight builds installed from it still buy and get
 * refunded under it, so its transactions and its `<bundle>.coins.<n>` products stay credited
 * until the owner retires it. */
export const legacyBundleId = "com.mikitahimpel.billet";

export const acceptedBundleIds: ReadonlyArray<string> = [appBundleId, legacyBundleId];

const legacyPackId = (pack: CoinPack) => pack.id.replace(appBundleId, legacyBundleId);

/** A legacy product id resolves to the pack it sold, whose canonical id is what gets credited. */
export const coinPackOf = (productId: string): CoinPack | undefined =>
  coinPacks.find((pack) => pack.id === productId || legacyPackId(pack) === productId);
