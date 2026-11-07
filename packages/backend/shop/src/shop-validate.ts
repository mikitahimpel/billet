import type { ShopCatalogItem } from "@billet/contracts-domain/shop-catalog";

/**
 * The rules a catalog entry must keep beyond its shape, or a sentence saying which it breaks. An
 * ink is sold under its own id and never discounted into the deals draw; a sale is a window with
 * an end after its start.
 */
export const shopItemProblem = (item: ShopCatalogItem): string | undefined => {
  if (item.kind === "ink" && !item.id.startsWith("ink-")) return "An ink's id starts with ink-.";
  if (item.kind !== "ink" && item.id.startsWith("ink-"))
    return "Only an ink's id starts with ink-.";
  if (item.kind === "ink" && item.deal !== undefined) return "An ink can't be in the daily deals.";
  if (item.sale !== undefined) {
    if (item.sale.until <= item.sale.from) return "A sale must end after it starts.";
    if (item.sale.price >= item.price) return "A sale price must be below the price.";
  }
  if (item.asset._tag === "Bundled" && item.asset.id.trim() !== item.asset.id) {
    return "The bundled asset id has spaces around it.";
  }
  return undefined;
};
