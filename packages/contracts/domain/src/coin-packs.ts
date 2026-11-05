import { Schema } from "effect";

/**
 * The coin packs the App Store will sell, as consumable in-app purchases, once payments are on
 * (the `payments` flag; docs/payments.md). Coins are Nooki's one currency: earned in play, and
 * bought here. This list is canonical. The app's copy
 * (`packages/ios/payments/Sources/Payments/Resources/coin-packs.json`) and the Xcode StoreKit configuration
 * must match it, which a test in `contracts-fixtures` checks. Prices are the US price tier in USD,
 * as App Store Connect shows it.
 *
 * The amounts and prices are placeholders until the owner sets them. Nothing is created in App
 * Store Connect yet.
 */
export const coinPacks = [
  { id: "com.mikitahimpel.billet.coins.100", coins: 100, price: "0.99" },
  { id: "com.mikitahimpel.billet.coins.550", coins: 550, price: "4.99" },
  { id: "com.mikitahimpel.billet.coins.1200", coins: 1200, price: "9.99" },
] as const;

export type CoinPack = (typeof coinPacks)[number];

/** The App Store product id of a pack. */
export const CoinPackId = Schema.Literals([coinPacks[0].id, coinPacks[1].id, coinPacks[2].id]);
export type CoinPackId = typeof CoinPackId.Type;

/** The pack sold under an App Store product id, if any. */
export const coinPackOf = (productId: string): CoinPack | undefined =>
  coinPacks.find(({ id }) => id === productId);

/** The app's bundle id: every App Store transaction for billet names it. */
export const appBundleId = "com.mikitahimpel.billet";
