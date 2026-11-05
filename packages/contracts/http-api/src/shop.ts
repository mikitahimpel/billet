import { Schema } from "effect";
import { UtcOffsetSeconds } from "@billet/contracts-domain/cat";
import { CoinEntry } from "@billet/contracts-domain/coins";
import { IdempotencyKey } from "@billet/contracts-domain/ids";
import {
  CollectionId,
  GiftReward,
  KnownRoomItemId,
  PairShop,
  ShopOffer,
} from "@billet/contracts-domain/shop";

/** `GET /v1/shop`: what the pair has. */
export const ShopResponse = PairShop;
export type ShopResponse = typeof ShopResponse.Type;

/**
 * The pair's local day is counted `utcOffsetSeconds` from UTC: the caller's clock. When absent,
 * the cat's clock once it is adopted, else UTC.
 */
const LocalClock = { utcOffsetSeconds: Schema.optionalKey(UtcOffsetSeconds) };

/**
 * `POST /v1/shop/orders`: buys one offer at the server's price, a piece at its deal price on the
 * pair's local day when it is one of the day's deals. `id` is the client's, repeated on every
 * retry; a retry answers with the first order and the pair as it is now.
 */
export const OrderRequest = Schema.Struct({ id: IdempotencyKey, offer: ShopOffer, ...LocalClock });
export type OrderRequest = typeof OrderRequest.Type;

/** The spend, and the pair after it. A piece bought leaves the wishlist. */
export const OrderResponse = Schema.Struct({ entry: CoinEntry, shop: ShopResponse });
export type OrderResponse = typeof OrderResponse.Type;

/** `PUT /v1/shop/wishlist`: adds a piece to the pair's wishlist, or takes it off. */
export const WishRequest = Schema.Struct({ item: KnownRoomItemId, wished: Schema.Boolean });
export type WishRequest = typeof WishRequest.Type;

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
