import { Schema } from "effect";
import { UtcOffsetSeconds } from "@billet/contracts-domain/cat";
import { CoinEntry } from "@billet/contracts-domain/coins";
import { ShopCatalogItem } from "@billet/contracts-domain/shop-catalog";
import { LayoutResult } from "@billet/contracts-domain/decor";
import { ExpectedPrice } from "./coins.ts";
import { IdempotencyKey } from "@billet/contracts-domain/ids";
import {
  CollectionId,
  GiftReward,
  RoomItemId,
  PairShop,
  ShopOffer,
} from "@billet/contracts-domain/shop";

/** `GET /v1/shop`: what the pair has. */
export const ShopResponse = PairShop;
export type ShopResponse = typeof ShopResponse.Type;

/** The local day: `utcOffsetSeconds` from UTC (the caller's), else the cat's clock, else UTC. */
const LocalClock = { utcOffsetSeconds: Schema.optionalKey(UtcOffsetSeconds) };

/**
 * Server price, never above `expectedPrice`; a day's deal at its deal price. Retry gets the first.
 */
export const OrderRequest = Schema.Struct({
  id: IdempotencyKey,
  offer: ShopOffer,
  expectedPrice: Schema.optionalKey(ExpectedPrice),
  ...LocalClock,
});
export type OrderRequest = typeof OrderRequest.Type;

/** The spend, and the pair after it. A piece bought leaves the wishlist. */
export const OrderResponse = Schema.Struct({ entry: CoinEntry, shop: ShopResponse });
export type OrderResponse = typeof OrderResponse.Type;

export const WishRequest = Schema.Struct({ item: RoomItemId, wished: Schema.Boolean });
export type WishRequest = typeof WishRequest.Type;

/** `POST /v1/shop/layout`: the layout as it is after the change, in `shop.layout`. */
export const LayoutResponse = Schema.Struct({ result: LayoutResult, shop: ShopResponse });
export type LayoutResponse = typeof LayoutResponse.Type;

/** `POST /v1/shop/gift`: opens the day's gift. Once a day for the pair; again answers the same. */
export const OpenGiftRequest = Schema.Struct(LocalClock);
export type OpenGiftRequest = typeof OpenGiftRequest.Type;

/** The gift's entry (amount 0 for a piece, which `ref` names), what it gave, and the pair after. */
export const OpenGiftResponse = Schema.Struct({
  entry: CoinEntry,
  reward: GiftReward,
  shop: ShopResponse,
});
export type OpenGiftResponse = typeof OpenGiftResponse.Type;

/** `POST /v1/shop/bonus`: collects a collection's bonus. Once ever; again answers the same. */
export const ClaimBonusRequest = Schema.Struct({ collection: CollectionId });
export type ClaimBonusRequest = typeof ClaimBonusRequest.Type;

export const ClaimBonusResponse = Schema.Struct({ entry: CoinEntry, shop: ShopResponse });
export type ClaimBonusResponse = typeof ClaimBonusResponse.Type;

/** Shelf order, no session. `version` is the ETag, so a client that has it gets a 304. */
export const ShopCatalogResponse = Schema.Struct({
  version: Schema.String.check(Schema.isPattern(/^[0-9a-f]{16}$/)),
  items: Schema.Array(ShopCatalogItem),
});
export type ShopCatalogResponse = typeof ShopCatalogResponse.Type;
