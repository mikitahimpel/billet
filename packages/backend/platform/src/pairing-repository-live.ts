import { and, eq, exists, gt, inArray, lte, ne, notExists, or, sql } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import {
  AlreadyPaired,
  InvalidInvite,
  PairingUnavailable,
} from "@billet/backend-pairing/pairing-error";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { PairId } from "@billet/contracts-domain/pair-id";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { invites, pairMembers, users } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = () => new PairingUnavailable({ reason: "directory-unavailable" });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodePairIds = Schema.decodeUnknownEffect(Schema.Array(Schema.Struct({ pairId: PairId })));
// A batch returns rows as stored, keyed by column name rather than by Drizzle field.
const decodeClaimerRows = Schema.decodeUnknownEffect(
  Schema.Array(Schema.Struct({ pair_id: PairId })),
);

const makePairingRepository = (db: DirectoryDatabase): PairingRepository["Service"] =>
  PairingRepository.of({
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
            .where(or(eq(pairMembers.userId, claimerId), eq(pairMembers.userId, invites.ownerId))),
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
          db
            .select({ pairId: pairMembers.pairId })
            .from(pairMembers)
            .where(eq(pairMembers.userId, claimerId)),
        ]).pipe(Effect.flatMap((results) => decodeClaimerRows(results[3]))),
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
  });

/** `PairingRepository` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const PairingRepositoryLive = (binding: D1Database): Layer.Layer<PairingRepository> =>
  Layer.effect(
    PairingRepository,
    Effect.map(openDirectoryDatabase(binding), makePairingRepository),
  );
