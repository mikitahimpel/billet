import { Schema } from "effect";
import { CoinEntry } from "@billet/contracts-domain/coins";
import { IdempotencyKey } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";
import { KnownRoomItemId, RoomItemId, ShopOffer } from "@billet/contracts-domain/shop";

const Balance = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/**
 * `GET /v1/shop`: what the pair has. `inks` starts with the free ink and `items` with the starter
 * pieces, then the rest in the order they were bought. `wishlist` is in the order it was wished.
 */
export const ShopResponse = Schema.Struct({
  balance: Balance,
  inks: Schema.Array(InkId),
  items: Schema.Array(RoomItemId),
  wishlist: Schema.Array(RoomItemId),
});
export type ShopResponse = typeof ShopResponse.Type;

/**
 * `POST /v1/shop/orders`: buys one offer at the server's price. `id` is the client's, repeated on
 * every retry; a retry answers with the first order and the pair as it is now.
 */
export const OrderRequest = Schema.Struct({ id: IdempotencyKey, offer: ShopOffer });
export type OrderRequest = typeof OrderRequest.Type;

/** The spend, and the pair after it. A piece bought leaves the wishlist. */
export const OrderResponse = Schema.Struct({ entry: CoinEntry, shop: ShopResponse });
export type OrderResponse = typeof OrderResponse.Type;

/** `PUT /v1/shop/wishlist`: adds a piece to the pair's wishlist, or takes it off. */
export const WishRequest = Schema.Struct({ item: KnownRoomItemId, wished: Schema.Boolean });
export type WishRequest = typeof WishRequest.Type;
