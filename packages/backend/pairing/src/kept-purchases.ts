import type { UserId } from "@billet/contracts-domain/ids";
import type { KeptPurchases } from "./pairing-repository.ts";

/**
 * Purchases are never deleted when a pair ends. The pair's inks and pieces are copied to each
 * partner, as the room doesn't say who bought what, and the coins are split evenly, the odd coin
 * to the first of the partners in id order, a stable tie-break. A demo partner is no keeper: the
 * person gets it all.
 */
export const splitKept = (
  keepers: ReadonlyArray<UserId>,
  shop: KeptPurchases,
): ReadonlyArray<readonly [UserId, KeptPurchases]> => {
  const sorted = [...new Set(keepers)].toSorted();
  const share = Math.floor(shop.coins / sorted.length);
  const extra = shop.coins - share * sorted.length;
  return sorted.map((userId, index) => [
    userId,
    { coins: share + (index < extra ? 1 : 0), inks: shop.inks, items: shop.items },
  ]);
};

/** What a new pair's room is given: everything its two members keep, once each. */
export const mergeKept = (kept: ReadonlyArray<KeptPurchases>): KeptPurchases => ({
  coins: kept.reduce((total, one) => total + one.coins, 0),
  inks: [...new Set(kept.flatMap((one) => one.inks))],
  items: [...new Set(kept.flatMap((one) => one.items))],
});
