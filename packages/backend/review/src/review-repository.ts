import { Context, type Effect, type Option, Schema } from "effect";
import { TokenHash } from "@billet/backend-auth/auth-repository";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import type { ReviewUnavailable } from "./review-error.ts";

/** What each stored table holds. A test in `platform` fails if a table's columns differ. */
export const StoredReviewPartner = Schema.Struct({ userId: UserId, createdAt: EpochMillis });
export type StoredReviewPartner = typeof StoredReviewPartner.Type;

export const StoredReviewCode = Schema.Struct({
  codeHash: TokenHash,
  partnerId: UserId,
  lastFour: Schema.String,
  createdAt: EpochMillis,
  /** The Cloudflare Access email of whoever made it. */
  createdBy: Schema.String,
  expiresAt: EpochMillis,
  revokedAt: Schema.NullOr(EpochMillis),
  claims: Schema.Int,
  lastClaimedAt: Schema.NullOr(EpochMillis),
});
export type StoredReviewCode = typeof StoredReviewCode.Type;

export const ReviewAction = Schema.Literals(["issue", "revoke", "wipe"]);
export type ReviewAction = typeof ReviewAction.Type;

export const StoredReviewChange = Schema.Struct({
  id: Schema.Int,
  at: EpochMillis,
  by: Schema.String,
  action: ReviewAction,
  lastFour: Schema.NullOr(Schema.String),
});
export type StoredReviewChange = typeof StoredReviewChange.Type;

export type NewReviewCode = Pick<
  StoredReviewCode,
  "codeHash" | "partnerId" | "lastFour" | "createdAt" | "createdBy" | "expiresAt"
>;

/**
 * The review partner, its codes and the admin's changes to them. Each method is one atomic write,
 * every storage failure is `ReviewUnavailable`, and raw codes never reach it.
 * `test/review-repository-contract.ts` is the behaviour any implementation must pass.
 */
export class ReviewRepository extends Context.Service<
  ReviewRepository,
  {
    /** The review partner, once one was opened. */
    readonly partner: Effect.Effect<Option.Option<UserId>, ReviewUnavailable>;
    /** Opens the partner as a user and records it, both or neither. */
    readonly createPartner: (
      partner: StoredReviewPartner,
    ) => Effect.Effect<void, ReviewUnavailable>;
    readonly isPartner: (userId: UserId) => Effect.Effect<boolean, ReviewUnavailable>;
    /** Revokes every earlier code, saves this one and records the change with `createdBy`. */
    readonly issue: (code: NewReviewCode) => Effect.Effect<void, ReviewUnavailable>;
    /** Revokes every code not revoked yet and records the change. */
    readonly revoke: (change: {
      readonly at: EpochMillis;
      readonly by: string;
    }) => Effect.Effect<void, ReviewUnavailable>;
    /** Records a change that touches no code, such as a wipe of the pair. */
    readonly record: (change: {
      readonly at: EpochMillis;
      readonly by: string;
      readonly action: ReviewAction;
    }) => Effect.Effect<void, ReviewUnavailable>;
    /** The partner a code pairs with, if it is neither revoked nor expired at `now`. */
    readonly liveCode: (
      codeHash: TokenHash,
      now: EpochMillis,
    ) => Effect.Effect<Option.Option<UserId>, ReviewUnavailable>;
    /** Counts a claim of the code at `at`. */
    readonly claimed: (
      codeHash: TokenHash,
      at: EpochMillis,
    ) => Effect.Effect<void, ReviewUnavailable>;
    /** The newest `limit` codes, newest first. */
    readonly codes: (
      limit: number,
    ) => Effect.Effect<ReadonlyArray<StoredReviewCode>, ReviewUnavailable>;
    /** The newest `limit` changes, newest first. */
    readonly changes: (
      limit: number,
    ) => Effect.Effect<ReadonlyArray<StoredReviewChange>, ReviewUnavailable>;
  }
>()("@billet/backend-review/ReviewRepository") {}
