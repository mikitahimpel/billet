import { Schema } from "effect";

/**
 * The stamp packs the App Store sells: consumable in-app purchases. This list is canonical. The
 * app's copy (`packages/ios/payments/Sources/Payments/Resources/stamp-packs.json`) and the Xcode StoreKit
 * configuration (`apps/ios/App/Billet.storekit`) must match it, which a test in
 * `contracts-fixtures` checks. Prices are the US price tier in USD, as App Store Connect shows it.
 */
export const stampPacks = [
  { id: "com.mikitahimpel.billet.stamps.100", stamps: 100, price: "0.99" },
  { id: "com.mikitahimpel.billet.stamps.550", stamps: 550, price: "4.99" },
  { id: "com.mikitahimpel.billet.stamps.1200", stamps: 1200, price: "9.99" },
] as const;

export type StampPack = (typeof stampPacks)[number];

/** The App Store product id of a pack. */
export const StampPackId = Schema.Literals([stampPacks[0].id, stampPacks[1].id, stampPacks[2].id]);
export type StampPackId = typeof StampPackId.Type;

/** The pack sold under an App Store product id, if any. */
export const stampPackOf = (productId: string): StampPack | undefined =>
  stampPacks.find(({ id }) => id === productId);

/** The app's bundle id: every App Store transaction for billet names it. */
export const appBundleId = "com.mikitahimpel.billet";
