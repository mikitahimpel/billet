import { and, eq, inArray, lt, lte, ne, notExists, notInArray } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import { AuthUnavailable } from "@billet/backend-auth/auth-error";
import { AuthRepository, PushTokenRecord } from "@billet/backend-auth/auth-repository";
import { UserId } from "@billet/contracts-domain/ids";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import {
  accountKeys,
  authAccounts,
  authChallenges,
  authSessions,
  authUsers,
  devices,
  invites,
  pairMembers,
  pushTokens,
  users,
} from "./directory-schema.ts";

/**
 * A device is made just before its session, so one without a session is either signed out by
 * Better Auth itself or mid sign-in. Only the first kind is old.
 */
const orphanGrace = 60 * 60 * 1000;

/**
 * Users no one can reach: no Apple link, no session, no account key and nothing of theirs. Only
 * the loser of two first Apple sign-ins at once leaves one (Better Auth writes the user, then the
 * link, and D1 can't hold both in one transaction). The grace keeps a sign-in in progress.
 */
const unreachableUsers = (db: DirectoryDatabase, before: number) =>
  db
    .select({ id: users.id })
    .from(users)
    .where(
      and(
        lt(users.createdAt, before),
        notExists(db.select().from(authAccounts).where(eq(authAccounts.userId, users.id))),
        notExists(db.select().from(authSessions).where(eq(authSessions.userId, users.id))),
        notExists(db.select().from(accountKeys).where(eq(accountKeys.userId, users.id))),
        notExists(db.select().from(devices).where(eq(devices.userId, users.id))),
        notExists(db.select().from(pairMembers).where(eq(pairMembers.userId, users.id))),
        notExists(db.select().from(invites).where(eq(invites.ownerId, users.id))),
      ),
    );

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = () => new AuthUnavailable({ reason: "directory-unavailable" });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodePushTokens = Schema.decodeUnknownEffect(Schema.Array(PushTokenRecord));
const decodeUserIds = Schema.decodeUnknownEffect(Schema.Array(Schema.Struct({ userId: UserId })));

const makeAuthRepository = (db: DirectoryDatabase): AuthRepository["Service"] =>
  AuthRepository.of({
    saveChallenge: (nonceHash, expiresAt) =>
      guarded(db.insert(authChallenges).values({ nonceHash, expiresAt })).pipe(Effect.asVoid),

    consumeChallenge: (nonceHash, now) =>
      guarded(
        db
          .delete(authChallenges)
          .where(eq(authChallenges.nonceHash, nonceHash))
          .returning({ expiresAt: authChallenges.expiresAt }),
      ).pipe(Effect.map((deleted) => deleted.some(({ expiresAt }) => expiresAt > now))),

    findAccountKey: (keyHash) =>
      guarded(
        db
          .select({ userId: accountKeys.userId })
          .from(accountKeys)
          .where(eq(accountKeys.keyHash, keyHash))
          .pipe(Effect.flatMap(decodeUserIds)),
      ).pipe(Effect.map(([row]) => (row === undefined ? Option.none() : Option.some(row.userId)))),

    saveAccountKey: (keyHash, userId, createdAt) =>
      guarded(
        db
          .insert(accountKeys)
          .values({ keyHash, userId, createdAt })
          .onConflictDoNothing({ target: accountKeys.keyHash })
          .returning({ keyHash: accountKeys.keyHash }),
      ).pipe(Effect.map((inserted) => inserted.length === 1)),

    savePushToken: (deviceId, record) => {
      const { environment, kind, token, updatedAt } = record;
      return guarded(
        atomically(db, [
          db
            .delete(pushTokens)
            .where(
              and(
                eq(pushTokens.token, token),
                eq(pushTokens.kind, kind),
                ne(pushTokens.deviceId, deviceId),
              ),
            ),
          db
            .insert(pushTokens)
            .values({ deviceId, kind, environment, token, updatedAt })
            .onConflictDoUpdate({
              target: [pushTokens.deviceId, pushTokens.kind],
              set: { environment, token, updatedAt },
            }),
        ]),
      ).pipe(Effect.asVoid);
    },

    listPushTokens: (deviceId) =>
      guarded(
        db
          .select({
            kind: pushTokens.kind,
            environment: pushTokens.environment,
            token: pushTokens.token,
            updatedAt: pushTokens.updatedAt,
          })
          .from(pushTokens)
          .where(eq(pushTokens.deviceId, deviceId))
          .pipe(Effect.flatMap(decodePushTokens)),
      ),

    deleteExpired: (now) => {
      // Better Auth's dates are ISO text, which sorts in time order.
      const nowIso = new Date(now).toISOString();
      return guarded(
        atomically(db, [
          db.delete(authChallenges).where(lte(authChallenges.expiresAt, now)),
          // An expired session goes with its device, which takes the push tokens with it.
          db
            .delete(devices)
            .where(
              inArray(
                devices.id,
                db
                  .select({ id: authSessions.deviceId })
                  .from(authSessions)
                  .where(lte(authSessions.expiresAt, nowIso)),
              ),
            ),
          db
            .delete(devices)
            .where(
              and(
                lt(devices.createdAt, now - orphanGrace),
                notInArray(devices.id, db.select({ id: authSessions.deviceId }).from(authSessions)),
              ),
            ),
          db
            .delete(authUsers)
            .where(inArray(authUsers.id, unreachableUsers(db, now - orphanGrace))),
          db.delete(users).where(inArray(users.id, unreachableUsers(db, now - orphanGrace))),
        ]),
      ).pipe(Effect.asVoid);
    },
  });

/** `AuthRepository` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const AuthRepositoryLive = (binding: D1Database): Layer.Layer<AuthRepository> =>
  Layer.effect(AuthRepository, Effect.map(openDirectoryDatabase(binding), makeAuthRepository));
