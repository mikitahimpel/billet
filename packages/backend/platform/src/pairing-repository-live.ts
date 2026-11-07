import { and, eq, exists, gt, inArray, lte, ne, notExists, or, sql } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import {
  AlreadyPaired,
  InvalidInvite,
  PairingUnavailable,
} from "@billet/backend-pairing/pairing-error";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import {
  blocks,
  invites,
  pairMembers,
  partnerNotices,
  partnerReports,
  users,
} from "./directory-schema.ts";
import { spanMethods } from "@billet/backend-observability/span-methods";

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = (cause: unknown) =>
  new PairingUnavailable({ reason: "directory-unavailable", cause });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodePairIds = Schema.decodeUnknownEffect(Schema.Array(Schema.Struct({ pairId: PairId })));
const decodePairedAt = Schema.decodeUnknownEffect(
  Schema.Array(Schema.Struct({ pairedAt: Schema.NullOr(EpochMillis) })),
);
const decodeMemberIds = Schema.decodeUnknownEffect(Schema.Array(Schema.Struct({ userId: UserId })));
// A batch returns rows as stored, keyed by column name rather than by Drizzle field.
const decodeClaimerRows = Schema.decodeUnknownEffect(
  Schema.Array(Schema.Struct({ pair_id: PairId })),
);

const makePairingRepository = (db: DirectoryDatabase): PairingRepository["Service"] =>
  PairingRepository.of(
    spanMethods("PairingRepository", {
      saveInvite: ({ codeHash, ownerId, createdAt, expiresAt }) =>
        guarded(
          atomically(db, [
            db
              .delete(invites)
              .where(or(eq(invites.ownerId, ownerId), lte(invites.expiresAt, createdAt))),
            db.insert(invites).select((qb) =>
              qb
                .select({
                  codeHash: sql<string>`${codeHash}`.as("code_hash"),
                  ownerId: users.id,
                  createdAt: sql<number>`${createdAt}`.as("created_at"),
                  expiresAt: sql<number>`${expiresAt}`.as("expires_at"),
                })
                .from(users)
                .where(
                  and(
                    eq(users.id, ownerId),
                    notExists(
                      db
                        .select({ userId: pairMembers.userId })
                        .from(pairMembers)
                        .where(eq(pairMembers.userId, ownerId)),
                    ),
                  ),
                ),
            ),
            db
              .select({ codeHash: invites.codeHash })
              .from(invites)
              .where(eq(invites.codeHash, codeHash)),
          ]),
        ).pipe(
          Effect.flatMap((results) =>
            results[2]?.length === 1 ? Effect.void : Effect.fail(new AlreadyPaired()),
          ),
        ),

      // Each step filters on what the one before it wrote, so a claim that fails its first condition
      // writes nothing, and the batch makes the winner's steps one transaction.
      claimInvite: ({ codeHash, claimerId, pairId, now }) => {
        const claimable = and(
          eq(invites.codeHash, codeHash),
          gt(invites.expiresAt, now),
          ne(invites.ownerId, claimerId),
          notExists(
            db
              .select({ userId: pairMembers.userId })
              .from(pairMembers)
              .where(
                or(eq(pairMembers.userId, claimerId), eq(pairMembers.userId, invites.ownerId)),
              ),
          ),
          notExists(
            db
              .select({ blockerId: blocks.blockerId })
              .from(blocks)
              .where(
                or(
                  and(eq(blocks.blockerId, claimerId), eq(blocks.blockedId, invites.ownerId)),
                  and(eq(blocks.blockerId, invites.ownerId), eq(blocks.blockedId, claimerId)),
                ),
              ),
          ),
        );
        const newPair = db
          .select({ userId: pairMembers.userId })
          .from(pairMembers)
          .where(eq(pairMembers.pairId, pairId));
        const newMember = {
          pairId: sql<string>`${pairId}`.as("pair_id"),
          createdAt: sql<number>`${now}`.as("created_at"),
        };

        return guarded(
          atomically(db, [
            db.insert(pairMembers).select((qb) =>
              qb
                .select({ userId: sql<string>`${claimerId}`.as("user_id"), ...newMember })
                .from(invites)
                .where(claimable),
            ),
            db.insert(pairMembers).select((qb) =>
              qb
                .select({ userId: invites.ownerId, ...newMember })
                .from(invites)
                .where(and(eq(invites.codeHash, codeHash), exists(newPair))),
            ),
            db.delete(invites).where(inArray(invites.ownerId, newPair)),
            // A new pair ends any notice that an earlier partner left.
            db.delete(partnerNotices).where(inArray(partnerNotices.userId, newPair)),
            db
              .select({ pairId: pairMembers.pairId })
              .from(pairMembers)
              .where(eq(pairMembers.userId, claimerId)),
          ]).pipe(Effect.flatMap((results) => decodeClaimerRows(results[4]))),
        ).pipe(
          Effect.flatMap(([claimer]): Effect.Effect<void, InvalidInvite | AlreadyPaired> => {
            if (claimer === undefined) return Effect.fail(new InvalidInvite());
            return claimer.pair_id === pairId ? Effect.void : Effect.fail(new AlreadyPaired());
          }),
        );
      },

      findPair: (userId) =>
        guarded(
          db
            .select({ pairId: pairMembers.pairId })
            .from(pairMembers)
            .where(eq(pairMembers.userId, userId))
            .pipe(Effect.flatMap(decodePairIds)),
        ).pipe(Effect.map(([member]) => Option.fromNullishOr(member?.pairId))),

      pairedAt: (pairId) =>
        guarded(
          db
            .select({ pairedAt: sql<number | null>`min(${pairMembers.createdAt})` })
            .from(pairMembers)
            .where(eq(pairMembers.pairId, pairId))
            .pipe(Effect.flatMap(decodePairedAt)),
        ).pipe(Effect.map(([row]) => Option.fromNullishOr(row?.pairedAt))),

      findMembers: (pairId) =>
        guarded(
          db
            .select({ userId: pairMembers.userId })
            .from(pairMembers)
            .where(eq(pairMembers.pairId, pairId))
            .pipe(Effect.flatMap(decodeMemberIds)),
        ).pipe(Effect.map((members) => members.map(({ userId }) => userId))),

      unpair: (userId) =>
        guarded(
          db
            .delete(pairMembers)
            .where(
              inArray(
                pairMembers.pairId,
                db
                  .select({ pairId: pairMembers.pairId })
                  .from(pairMembers)
                  .where(eq(pairMembers.userId, userId)),
              ),
            ),
        ).pipe(Effect.asVoid),

      block: ({ blocker, blocked, at }) =>
        guarded(
          atomically(db, [
            db
              .insert(blocks)
              .values({ blockerId: blocker, blockedId: blocked, createdAt: at })
              .onConflictDoNothing(),
            db
              .delete(pairMembers)
              .where(
                inArray(
                  pairMembers.pairId,
                  db
                    .select({ pairId: pairMembers.pairId })
                    .from(pairMembers)
                    .where(eq(pairMembers.userId, blocker)),
                ),
              ),
          ]),
        ).pipe(Effect.asVoid),

      saveReport: ({ id, reporter, reported, pairId, reason, details, at }) =>
        guarded(
          db.insert(partnerReports).values({
            id,
            reporterId: reporter,
            reportedId: reported,
            pairId,
            reason,
            details: details ?? null,
            createdAt: at,
          }),
        ).pipe(Effect.asVoid),
    }),
  );

/** `PairingRepository` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const PairingRepositoryLive = (binding: D1Database): Layer.Layer<PairingRepository> =>
  Layer.effect(
    PairingRepository,
    Effect.map(openDirectoryDatabase(binding), makePairingRepository),
  );
