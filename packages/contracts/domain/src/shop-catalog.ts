import { Schema } from "effect";
import { EpochMillis } from "./ids.ts";

const slug = Schema.String.check(
  Schema.isPattern(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/),
  Schema.isMaxLength(40),
);

/**
 * What an item is, such as `furniture`, `decor`, `mochi`, `room`, `ink`, `coat` or `accessory`.
 * Open on purpose: a client skips a kind it does not know instead of failing the whole catalog.
 */
export const ShopItemKind = slug.pipe(Schema.brand("ShopItemKind"));
export type ShopItemKind = typeof ShopItemKind.Type;

/** The shelf an item is listed on, such as `furniture` or `daily-deals`. Open like the kind. */
export const ShopSection = slug.pipe(Schema.brand("ShopSection"));
export type ShopSection = typeof ShopSection.Type;

export const ShopRarity = Schema.Literals(["common", "rare", "epic", "legendary"]);
export type ShopRarity = typeof ShopRarity.Type;

/** An item's picture in R2, served at `/v1/shop/art/<key>`; the name is a content hash. */
export const ShopPictureKey = Schema.String.check(
  Schema.isPattern(/^[0-9a-f]{16}\.(webp|png|jpg)$/),
);
export type ShopPictureKey = typeof ShopPictureKey.Type;

/**
 * What draws the item: a model or image the app already bundles under `id`, or a picture the
 * admin uploaded. A client that does not bundle `id` skips the item.
 */
export const ShopAsset = Schema.TaggedUnion({
  Bundled: { id: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(60)) },
  Picture: { key: ShopPictureKey },
});
export type ShopAsset = typeof ShopAsset.Type;

const Coins = Schema.Int.check(
  Schema.isGreaterThanOrEqualTo(0),
  Schema.isLessThanOrEqualTo(100_000),
);

/** A price that holds from `from` up to, not including, `until`. */
export const ShopSale = Schema.Struct({ price: Coins, from: EpochMillis, until: EpochMillis });
export type ShopSale = typeof ShopSale.Type;

/**
 * Puts an item in the daily-deals draw at `discount` (0.25 is 25% off). The draw is a function of
 * the pool in `order`, so moving an item changes which deals a pair draws.
 */
export const ShopDeal = Schema.Struct({
  discount: Schema.Number.check(Schema.isGreaterThan(0), Schema.isLessThan(1)),
  order: Schema.Int,
});
export type ShopDeal = typeof ShopDeal.Type;

/**
 * One item of the shop's catalog. `blurb` and `name` may hold `{cat}`, which the app replaces with
 * the cat's name. `deal` is the item's place in the daily-deals draw, if it has one.
 * `minBuild` is the first app build that may show the item.
 */
export const ShopCatalogItem = Schema.Struct({
  id: Schema.String.check(
    Schema.isPattern(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/),
    Schema.isMaxLength(40),
  ),
  kind: ShopItemKind,
  name: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(60)),
  blurb: Schema.optionalKey(Schema.String.check(Schema.isMaxLength(160))),
  mood: Schema.optionalKey(Schema.String.check(Schema.isMaxLength(20))),
  rarity: ShopRarity,
  price: Coins,
  sale: Schema.optionalKey(ShopSale),
  deal: Schema.optionalKey(ShopDeal),
  section: ShopSection,
  sortOrder: Schema.Int,
  plus: Schema.optionalKey(Schema.Boolean),
  isNew: Schema.optionalKey(Schema.Boolean),
  asset: ShopAsset,
  minBuild: Schema.optionalKey(Schema.Int.check(Schema.isGreaterThanOrEqualTo(1))),
});
export type ShopCatalogItem = typeof ShopCatalogItem.Type;

/** What `item` costs at `at`: its sale price inside the sale's window, else its price. */
export const shopPriceAt = (
  item: Pick<ShopCatalogItem, "price" | "sale">,
  at: EpochMillis,
): number =>
  item.sale !== undefined && at >= item.sale.from && at < item.sale.until
    ? item.sale.price
    : item.price;

const BookEntry = Schema.Struct({ id: Schema.String, price: Schema.Int });

/**
 * The prices the room decides an order by, taken from the catalog at the moment of the order:
 * only active items, each at its price then. The client's idea of a price never gets here.
 * `deals` are the items in the daily-deals draw, in the order the draw takes them.
 */
export const PriceBook = Schema.Struct({
  items: Schema.Array(BookEntry),
  inks: Schema.Array(BookEntry),
  deals: Schema.Array(Schema.Struct({ item: Schema.String, discount: Schema.Number })),
});
export type PriceBook = typeof PriceBook.Type;

/**
 * What a buy or an order is decided by. `book` is the server's catalog prices; `expectedPrice` is
 * the price the buyer saw: a price above it is refused (`PriceChanged`), a lower one is charged.
 * Without a book the room uses the canonical lists in `shop.ts` and `inks.ts`.
 */
export const PriceTerms = Schema.Struct({
  book: Schema.optionalKey(PriceBook),
  expectedPrice: Schema.optionalKey(Schema.Int),
});
export type PriceTerms = typeof PriceTerms.Type;
