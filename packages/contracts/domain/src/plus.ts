import { Schema } from "effect";
import { InkId, freeInk, inkOf, inks } from "./inks.ts";
import { PostageId, postage, postageOf } from "./postage.ts";
import { RoomItemId, roomItemOf, roomItems, starterItems } from "./shop.ts";

/** The App Store subscription group both plans belong to. One level: the plans are the same
 * thing billed differently. */
export const plusGroup = "Ourio Plus";

export const PlusPlan = Schema.Literals(["monthly", "yearly"]);
export type PlusPlan = typeof PlusPlan.Type;

/** Canonical: the app's StoreKit configuration must match (tested in `contracts-fixtures`).
 * Prices: US tier in USD, placeholders until the owner sets them. `parcels` is how many parcels
 * one paid period brings, one a month. */
export const plusProducts = [
  { id: "com.ourio.app.plus.monthly", plan: "monthly", price: "3.99", parcels: 1 },
  { id: "com.ourio.app.plus.yearly", plan: "yearly", price: "29.99", parcels: 12 },
] as const;

export type PlusProduct = (typeof plusProducts)[number];

export const PlusProductId = Schema.Literals([plusProducts[0].id, plusProducts[1].id]);
export type PlusProductId = typeof PlusProductId.Type;

export const plusProductOf = (productId: string): PlusProduct | undefined =>
  plusProducts.find((product) => product.id === productId);

export const plusProductFor = (plan: PlusPlan): PlusProduct =>
  plan === "monthly" ? plusProducts[0] : plusProducts[1];

/**
 * The dearest a piece a parcel may hold, in coins, inclusive. The top pieces (the donut bed at
 * 380 and the tower at 540, each four weeks or more of play) stay earned or bought, so Plus never
 * becomes the cheap way to the rarest things. See docs/subscription.md#parcels.
 */
export const parcelPriceCeiling = 320;

/** `parcel:<transactionId>` for a month, `parcel:<transactionId>:<n>` for the nth month of a
 * year. Derived from Apple's transaction, so the same paid month is the same parcel everywhere. */
export const ParcelId = Schema.String.check(
  Schema.isPattern(/^parcel:[A-Za-z0-9._-]{1,80}(:([1-9]|1[0-2]))?$/),
).pipe(Schema.brand("ParcelId"));
export type ParcelId = typeof ParcelId.Type;

/** What a parcel may become: one room piece, ink, stamp or seal. Never a set or a treat. */
export const ParcelOffer = Schema.TaggedUnion({
  Ink: { ink: InkId },
  Item: { item: RoomItemId },
  Postage: { postage: PostageId },
});
export type ParcelOffer = typeof ParcelOffer.Type;

/** The coin price the shop sells it for, or undefined when the shop does not sell it. */
export const priceOfParcelOffer = (offer: ParcelOffer): number | undefined => {
  switch (offer._tag) {
    case "Ink":
      return offer.ink === freeInk ? undefined : inkOf(offer.ink)?.price;
    case "Item":
      return starterItems.includes(offer.item) ? undefined : roomItemOf(offer.item)?.price;
    case "Postage":
      return postageOf(offer.postage)?.price;
  }
};

export const fitsParcel = (offer: ParcelOffer): boolean => {
  const price = priceOfParcelOffer(offer);
  return price !== undefined && price <= parcelPriceCeiling;
};

/** Everything a parcel may hold, whether the pair owns it or not. */
export const parcelChoices: ReadonlyArray<ParcelOffer> = [
  ...roomItems.map((item) => ParcelOffer.cases.Item.make({ item: item.id })),
  ...inks.map((ink) => ParcelOffer.cases.Ink.make({ ink: ink.id })),
  ...postage.map((entry) => ParcelOffer.cases.Postage.make({ postage: entry.id })),
].filter(fitsParcel);
