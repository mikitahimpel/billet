import { Schema } from "effect";
import { ParcelId, ParcelOffer, PlusPlan } from "@billet/contracts-domain/plus";
import { ShopResponse } from "./shop.ts";

const isoDate = Schema.String.check(Schema.isNonEmpty());
const count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/**
 * The pair's Plus as the caller sees it. `Active`, `Ending` and `Grace` are the caller's own
 * subscription; `Shared` is the partner's, with no plan, price or dates, so the partner never
 * learns that the other cancelled, failed to pay or was refunded. `Ended`: the pair had Plus and
 * has it no longer; parcels not opened yet still open. Dates are ISO 8601 UTC.
 */
export const PlusState = Schema.TaggedUnion({
  None: {},
  Active: { plan: PlusPlan, renewsOn: isoDate },
  /** Renewal is off; Plus runs until `until`. */
  Ending: { plan: PlusPlan, until: isoDate },
  /** Apple could not take the payment and is retrying; parcels keep coming. */
  Grace: { plan: PlusPlan },
  Shared: {},
  Ended: {},
});
export type PlusState = typeof PlusState.Type;

export const Parcel = Schema.Struct({ id: ParcelId, arrived: isoDate });
export type Parcel = typeof Parcel.Type;

/**
 * `GET /v1/plus`. `parcels`: waiting to be opened, oldest first, from either partner's Plus.
 * `nextParcel` is absent when none is due. `bothPay`: each partner has a subscription.
 * `choicesLeft`: what a parcel could still become for this pair.
 */
export const PlusResponse = Schema.Struct({
  state: PlusState,
  parcels: Schema.Array(Parcel),
  opened: count,
  nextParcel: Schema.optionalKey(isoDate),
  bothPay: Schema.Boolean,
  choicesLeft: count,
});
export type PlusResponse = typeof PlusResponse.Type;

/**
 * `POST /v1/plus/subscribe`: StoreKit 2's `Transaction.jwsRepresentation` of a Plus plan, and
 * the subscription's `RenewalInfo.jwsRepresentation` when the phone has it, so renewal and grace
 * are right without waiting for Apple's notification.
 */
export const SubscribeRequest = Schema.Struct({
  signedTransaction: Schema.String.check(Schema.isNonEmpty()),
  signedRenewalInfo: Schema.optionalKey(Schema.String.check(Schema.isNonEmpty())),
});
export type SubscribeRequest = typeof SubscribeRequest.Type;

/** Dev stage only: what Apple would do to a Plus subscription, under a made-up id. */
export const MockPlusRequest = Schema.Struct({
  plan: PlusPlan,
  transactionId: Schema.String.check(Schema.isPattern(/^mock-[A-Za-z0-9-]{1,64}$/)),
  kind: Schema.Literals(["subscribe", "renew", "cancel", "fail", "expire", "refund"]),
});
export type MockPlusRequest = typeof MockPlusRequest.Type;

/** `POST /v1/plus/parcels/open`: turns a waiting parcel into one piece. The same parcel and
 * offer again answers as the first open did. */
export const OpenParcelRequest = Schema.Struct({ parcel: ParcelId, offer: ParcelOffer });
export type OpenParcelRequest = typeof OpenParcelRequest.Type;

export const OpenParcelResponse = Schema.Struct({ plus: PlusResponse, shop: ShopResponse });
export type OpenParcelResponse = typeof OpenParcelResponse.Type;
