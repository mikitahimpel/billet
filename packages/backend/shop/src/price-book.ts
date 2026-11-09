import {
  type PriceBook,
  type ShopCatalogItem,
  shopPriceAt,
} from "@billet/contracts-domain/shop-catalog";

/** An item that is not here is not sold, whatever the client asks for. */
export const priceBookOf = (items: ReadonlyArray<ShopCatalogItem>, at: number): PriceBook => ({
  items: items
    .filter((item) => item.kind !== "ink")
    .map((item) => ({ id: item.id, price: shopPriceAt(item, at) })),
  inks: items
    .filter((item) => item.kind === "ink")
    .map((item) => ({ id: item.id, price: shopPriceAt(item, at) })),
  deals: items
    .flatMap((item) =>
      item.kind !== "ink" && item.deal !== undefined
        ? [{ item: item.id, discount: item.deal.discount, order: item.deal.order }]
        : [],
    )
    .toSorted((a, b) => a.order - b.order)
    .map(({ item, discount }) => ({ item, discount })),
});
