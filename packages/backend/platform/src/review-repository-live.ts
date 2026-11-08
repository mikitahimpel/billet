import { and, desc, eq, gt, isNull, sql } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import { spanMethods } from "@billet/backend-observability/span-methods";
import { ReviewUnavailable } from "@billet/backend-review/review-error";
import {
  ReviewRepository,
  StoredReviewChange,
  StoredReviewCode,
} from "@billet/backend-review/review-repository";
import { UserId } from "@billet/contracts-domain/ids";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { reviewChanges, reviewCodes, reviewPartners, users } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = (cause: unknown) =>
  new ReviewUnavailable({ reason: "directory-unavailable", cause });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodeUserIds = Schema.decodeUnknownEffect(Schema.Array(Schema.Struct({ userId: UserId })));
const decodeCodes = Schema.decodeUnknownEffect(Schema.Array(StoredReviewCode));
const decodeChanges = Schema.decodeUnknownEffect(Schema.Array(StoredReviewChange));

const makeReviewRepository = (db: DirectoryDatabase): ReviewRepository["Service"] =>
  ReviewRepository.of(
    spanMethods("ReviewRepository", {
      partner: guarded(
        db
          .select({ userId: reviewPartners.userId })
          .from(reviewPartners)
          .orderBy(reviewPartners.createdAt)
          .limit(1)
          .pipe(Effect.flatMap(decodeUserIds)),
      ).pipe(Effect.map(([row]) => Option.fromNullishOr(row?.userId))),

      createPartner: ({ userId, createdAt }) =>
        guarded(
          atomically(db, [
            db.insert(users).values({ id: userId, createdAt }),
            db.insert(reviewPartners).values({ userId, createdAt }),
          ]),
        ).pipe(Effect.asVoid),

      isPartner: (userId) =>
        guarded(
          db
            .select({ userId: reviewPartners.userId })
            .from(reviewPartners)
            .where(eq(reviewPartners.userId, userId))
            .pipe(Effect.flatMap(decodeUserIds)),
        ).pipe(Effect.map((rows) => rows.length > 0)),

      issue: (code) =>
        guarded(
          atomically(db, [
            db
              .update(reviewCodes)
              .set({ revokedAt: code.createdAt })
              .where(isNull(reviewCodes.revokedAt)),
            db.insert(reviewCodes).values(code),
            db.insert(reviewChanges).values({
              at: code.createdAt,
              by: code.createdBy,
              action: "issue",
              lastFour: code.lastFour,
            }),
          ]),
        ).pipe(Effect.asVoid),

      revoke: ({ at, by }) =>
        guarded(
          atomically(db, [
            db.update(reviewCodes).set({ revokedAt: at }).where(isNull(reviewCodes.revokedAt)),
            db.insert(reviewChanges).values({ at, by, action: "revoke", lastFour: null }),
          ]),
        ).pipe(Effect.asVoid),

      record: ({ at, by, action }) =>
        guarded(db.insert(reviewChanges).values({ at, by, action, lastFour: null })).pipe(
          Effect.asVoid,
        ),

      liveCode: (codeHash, now) =>
        guarded(
          db
            .select({ userId: reviewCodes.partnerId })
            .from(reviewCodes)
            .where(
              and(
                eq(reviewCodes.codeHash, codeHash),
                isNull(reviewCodes.revokedAt),
                gt(reviewCodes.expiresAt, now),
              ),
            )
            .pipe(Effect.flatMap(decodeUserIds)),
        ).pipe(Effect.map(([row]) => Option.fromNullishOr(row?.userId))),

      claimed: (codeHash, at) =>
        guarded(
          db
            .update(reviewCodes)
            .set({ claims: sql`${reviewCodes.claims} + 1`, lastClaimedAt: at })
            .where(eq(reviewCodes.codeHash, codeHash)),
        ).pipe(Effect.asVoid),

      codes: (limit) =>
        guarded(
          db
            .select()
            .from(reviewCodes)
            .orderBy(desc(reviewCodes.createdAt))
            .limit(limit)
            .pipe(Effect.flatMap(decodeCodes)),
        ),

      changes: (limit) =>
        guarded(
          db
            .select()
            .from(reviewChanges)
            .orderBy(desc(reviewChanges.id))
            .limit(limit)
            .pipe(Effect.flatMap(decodeChanges)),
        ),
    }),
  );

/** `ReviewRepository` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const ReviewRepositoryLive = (binding: D1Database): Layer.Layer<ReviewRepository> =>
  Layer.effect(ReviewRepository, Effect.map(openDirectoryDatabase(binding), makeReviewRepository));
