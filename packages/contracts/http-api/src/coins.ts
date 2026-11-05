import { Schema } from "effect";
import { UtcOffsetSeconds } from "@billet/contracts-domain/cat";
import { CoinEntry, EarnEvent } from "@billet/contracts-domain/coins";
import { IdempotencyKey } from "@billet/contracts-domain/ids";
import { InkId, KnownInkId } from "@billet/contracts-domain/inks";

const Balance = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/**
 * `GET /v1/coins?after=<entry id>&limit=<1-100>`: the pair's balance and its wallet entries after
 * `after` (from the first when absent), oldest first.
 */
export const CoinsResponse = Schema.Struct({
  balance: Balance,
  entries: Schema.Array(CoinEntry),
});
export type CoinsResponse = typeof CoinsResponse.Type;

/**
 * `POST /v1/shop/buy`: buys one item at its catalog price. `id` is the client's, repeated on every
 * retry; a retry answers with the first buy. Only inks are sold so far.
 */
export const BuyRequest = Schema.Struct({ id: IdempotencyKey, item: KnownInkId });
export type BuyRequest = typeof BuyRequest.Type;

/** The spend, the balance after it, what it granted and everything the pair now owns. */
export const BuyResponse = Schema.Struct({
  entry: CoinEntry,
  balance: Balance,
  granted: Schema.Array(InkId),
  owned: Schema.Array(InkId),
});
export type BuyResponse = typeof BuyResponse.Type;

/**
 * `POST /v1/coins/earn`: pays something the couple did in the app. Once per ref: the same event
 * again answers with the first entry. The day the cap counts is `utcOffsetSeconds` from UTC: the
 * caller's clock, else the cat's, else UTC.
 */
export const EarnRequest = Schema.Struct({
  event: EarnEvent,
  utcOffsetSeconds: Schema.optionalKey(UtcOffsetSeconds),
});
export type EarnRequest = typeof EarnRequest.Type;

/** The balance, and the entry: absent when the day's cap was already met. */
export const EarnResponse = Schema.Struct({
  balance: Balance,
  entry: Schema.optionalKey(CoinEntry),
});
export type EarnResponse = typeof EarnResponse.Type;
