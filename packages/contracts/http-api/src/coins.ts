import { Schema } from "effect";
import { UtcOffsetSeconds } from "@billet/contracts-domain/cat";
import { CoinEntry, EarnEvent } from "@billet/contracts-domain/coins";
import { IdempotencyKey } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";

/** Prices above this are refused with `PriceChanged`, lower ones charged. Absent: any price. */
export const ExpectedPrice = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** Signed: below 0 after a refund of coins already spent, until earning pays it down. */
const Balance = Schema.Int;

/** `GET /v1/coins?after=<entry id>&limit=<1-100>`: entries after `after`, oldest first. */
export const CoinsResponse = Schema.Struct({
  balance: Balance,
  entries: Schema.Array(CoinEntry),
});
export type CoinsResponse = typeof CoinsResponse.Type;

/** `POST /v1/shop/buy` (inks only). The client's `id` repeats on retry and gets the first buy. */
export const BuyRequest = Schema.Struct({
  id: IdempotencyKey,
  item: InkId,
  expectedPrice: Schema.optionalKey(ExpectedPrice),
});
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
 * Once per ref, a repeat answers the first entry. The cap's day: caller's, else cat's, else UTC.
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
