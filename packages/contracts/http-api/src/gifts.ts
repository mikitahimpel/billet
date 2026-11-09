import { Schema } from "effect";
import { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";

/** Up to `max` UTF-16 units. The app trims before it sends. */
const Text = (max: number) => Schema.String.check(Schema.isMaxLength(max));

/** 1 to 200 units, not only whitespace. */
export const GiftTitle = Schema.String.check(
  Schema.makeFilter(
    (text) =>
      (text.trim().length > 0 && text.length <= 200) ||
      "expected 1 to 200 characters, not only whitespace",
  ),
);
export type GiftTitle = typeof GiftTitle.Type;

/** Each phone keeps its own calendar, so a wish carries a title and day, not a calendar entry. */
export const GiftOccasion = Schema.Struct({
  title: Schema.String.check(
    Schema.makeFilter(
      (text) =>
        (text.trim().length > 0 && text.length <= 60) ||
        "expected 1 to 60 characters, not only whitespace",
    ),
  ),
  date: EpochMillis,
});
export type GiftOccasion = typeof GiftOccasion.Type;

/**
 * The giver's `GiftPlan` is never sent to the owner. `giftedBy` appears only once it arrived.
 */
export const GiftWish = Schema.Struct({
  /** Chosen by the client. */
  id: IdempotencyKey,
  owner: UserId,
  title: GiftTitle,
  link: Text(2048),
  price: Text(40),
  /** Colour, size or model, for the giver. */
  note: Text(500),
  mostWanted: Schema.Boolean,
  occasion: Schema.optionalKey(GiftOccasion),
  addedAt: EpochMillis,
  receivedAt: Schema.optionalKey(EpochMillis),
  giftedBy: Schema.optionalKey(UserId),
});
export type GiftWish = typeof GiftWish.Type;

export const GiftStage = Schema.Literals(["planning", "bought"]);
export type GiftStage = typeof GiftStage.Type;

/** The caller's own secret promise to gift one of the partner's wishes. */
export const GiftPlan = Schema.Struct({ wish: IdempotencyKey, stage: GiftStage });
export type GiftPlan = typeof GiftPlan.Type;

/** What a partner likes, filled in by that partner. Every field may be empty. */
export const Loves = Schema.Struct({
  sizes: Text(200),
  flowers: Text(200),
  coffee: Text(200),
  sweets: Text(200),
  allergies: Text(200),
  /** Gifts to avoid. */
  avoid: Text(200),
});
export type Loves = typeof Loves.Type;

export const PartnerLoves = Schema.Struct({ user: UserId, loves: Loves });
export type PartnerLoves = typeof PartnerLoves.Type;

/**
 * `plans`: only the caller's own. `surprise`: the partner plans one of the caller's open wishes.
 */
export const GiftsResponse = Schema.Struct({
  wishes: Schema.Array(GiftWish),
  plans: Schema.Array(GiftPlan),
  surprise: Schema.Boolean,
  loves: Schema.Array(PartnerLoves),
});
export type GiftsResponse = typeof GiftsResponse.Type;

export const SaveGiftWishRequest = Schema.Struct({
  id: IdempotencyKey,
  title: GiftTitle,
  link: Text(2048),
  price: Text(40),
  note: Text(500),
  mostWanted: Schema.Boolean,
  /** Absent clears it. */
  occasion: Schema.optionalKey(GiftOccasion),
});
export type SaveGiftWishRequest = typeof SaveGiftWishRequest.Type;

/** `DELETE /v1/gifts/wishes`: deletes one of the caller's wishes, and any plan for it. */
export const DeleteGiftWishRequest = Schema.Struct({ id: IdempotencyKey });
export type DeleteGiftWishRequest = typeof DeleteGiftWishRequest.Type;

/** No `stage` lets the plan go. A wish has one giver at a time. */
export const SetGiftPlanRequest = Schema.Struct({
  wish: IdempotencyKey,
  stage: Schema.optionalKey(GiftStage),
});
export type SetGiftPlanRequest = typeof SetGiftPlanRequest.Type;

/** `PUT /v1/gifts/received`: the owner says a wish arrived, or takes that back. */
export const MarkGiftReceivedRequest = Schema.Struct({
  wish: IdempotencyKey,
  received: Schema.Boolean,
});
export type MarkGiftReceivedRequest = typeof MarkGiftReceivedRequest.Type;

export const SaveLovesRequest = Schema.Struct({ loves: Loves });
export type SaveLovesRequest = typeof SaveLovesRequest.Type;
