import { Schema } from "effect";
import { EpochMillis } from "./ids.ts";

const slug = Schema.String.check(
  Schema.isPattern(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/),
  Schema.isMaxLength(40),
);

/** Open on purpose: a client skips a kind it does not know instead of failing the catalog. */
export const ShopItemKind = slug.pipe(Schema.brand("ShopItemKind"));
export type ShopItemKind = typeof ShopItemKind.Type;

/** Open like the kind. */
export const ShopSection = slug.pipe(Schema.brand("ShopSection"));
export type ShopSection = typeof ShopSection.Type;

export const ShopRarity = Schema.Literals(["common", "rare", "epic", "legendary"]);
export type ShopRarity = typeof ShopRarity.Type;

/** Served at `/v1/shop/art/<key>`; the name is a content hash. */
export const ShopPictureKey = Schema.String.check(
  Schema.isPattern(/^[0-9a-f]{16}\.(webp|png|jpg)$/),
);
export type ShopPictureKey = typeof ShopPictureKey.Type;

/** A client that does not bundle a `Bundled` id skips the item. */
export const ShopAsset = Schema.TaggedUnion({
  Bundled: { id: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(60)) },
  Picture: { key: ShopPictureKey },
});
export type ShopAsset = typeof ShopAsset.Type;

const Coins = Schema.Int.check(
  Schema.isGreaterThanOrEqualTo(0),
  Schema.isLessThanOrEqualTo(100_000),
);

/** `until` is exclusive. */
export const ShopSale = Schema.Struct({ price: Coins, from: EpochMillis, until: EpochMillis });
export type ShopSale = typeof ShopSale.Type;

/** `discount` 0.25 is 25% off. The draw depends on `order`, so moving an item changes which
 * deals a pair draws. */
export const ShopDeal = Schema.Struct({
  discount: Schema.Number.check(Schema.isGreaterThan(0), Schema.isLessThan(1)),
  order: Schema.Int,
});
export type ShopDeal = typeof ShopDeal.Type;

/** `blurb` and `name` may hold `{cat}`, which the app replaces with the cat's name. `minBuild`
 * is the first app build that may show the item. */
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

export const shopPriceAt = (
  item: Pick<ShopCatalogItem, "price" | "sale">,
  at: EpochMillis,
): number =>
  item.sale !== undefined && at >= item.sale.from && at < item.sale.until
    ? item.sale.price
    : item.price;

const BookEntry = Schema.Struct({ id: Schema.String, price: Schema.Int });

/** Active items at their catalog price when the order is made; the client's price never gets
 * here. `deals` in the order the draw takes them. */
export const PriceBook = Schema.Struct({
  items: Schema.Array(BookEntry),
  inks: Schema.Array(BookEntry),
  deals: Schema.Array(Schema.Struct({ item: Schema.String, discount: Schema.Number })),
});
export type PriceBook = typeof PriceBook.Type;

/** A price above `expectedPrice` is refused (`PriceChanged`), a lower one charged. Without a
 * `book` the room uses the canonical lists in `shop.ts` and `inks.ts`. */
export const PriceTerms = Schema.Struct({
  book: Schema.optionalKey(PriceBook),
  expectedPrice: Schema.optionalKey(Schema.Int),
});
export type PriceTerms = typeof PriceTerms.Type;
