import { Schema } from "effect";
import { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";

/** Up to `max` UTF-16 units. The app trims before it sends. */
const Text = (max: number) => Schema.String.check(Schema.isMaxLength(max));

/** What a wish is called: 1 to 200 units, not only whitespace. */
export const GiftTitle = Schema.String.check(
  Schema.makeFilter(
    (text) =>
      (text.trim().length > 0 && text.length <= 200) ||
      "expected 1 to 200 characters, not only whitespace",
  ),
);
export type GiftTitle = typeof GiftTitle.Type;

/**
 * The day a wish is for, such as a birthday, as the owner's phone named it. Each phone keeps its
 * own calendar, so the wish carries the title and the day rather than a calendar entry.
 */
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
 * One partner's wish, as both partners see it. Nothing here says who plans to gift it: that is the
 * giver's `GiftPlan`, which the owner never receives. `giftedBy` appears only once it arrived.
 */
export const GiftWish = Schema.Struct({
  /** The client's, chosen when the wish is made. */
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
 * `GET /v1/gifts`, and the answer to every change: the pair's wishes as the caller may see them.
 * `plans` holds only the caller's own. `surprise` is true while the partner plans to gift one of
 * the caller's open wishes, without saying which. `wishes` is oldest first.
 */
export const GiftsResponse = Schema.Struct({
  wishes: Schema.Array(GiftWish),
  plans: Schema.Array(GiftPlan),
  surprise: Schema.Boolean,
  loves: Schema.Array(PartnerLoves),
});
export type GiftsResponse = typeof GiftsResponse.Type;

/** `PUT /v1/gifts/wishes`: makes the caller's wish, or changes one they made. */
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

/**
 * `PUT /v1/gifts/plans`: the caller plans to gift the partner's wish, moves the plan on, or, with
 * no `stage`, lets it go. A wish has one giver at a time.
 */
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

/** `PUT /v1/gifts/loves`: the caller's own "What I love". */
export const SaveLovesRequest = Schema.Struct({ loves: Loves });
export type SaveLovesRequest = typeof SaveLovesRequest.Type;
