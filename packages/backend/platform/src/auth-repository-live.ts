import { and, eq, inArray, lte, ne, sql } from "drizzle-orm";
import { Effect, Layer, Schema } from "effect";
import { AuthUnavailable } from "@billet/backend-auth/auth-error";
import {
  AuthRepository,
  PushTokenRecord,
  SessionRecord,
} from "@billet/backend-auth/auth-repository";
import { UserId } from "@billet/contracts-domain/ids";
import { type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { authChallenges, devices, pushTokens, sessions, users } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = () => new AuthUnavailable({ reason: "directory-unavailable" });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

interface Compilable {
  readonly toSQL: () => { readonly sql: string; readonly params: ReadonlyArray<unknown> };
}

const decodeSession = Schema.decodeUnknownEffect(SessionRecord);
const decodePushTokens = Schema.decodeUnknownEffect(Schema.Array(PushTokenRecord));
const decodeCreatedUser = Schema.decodeUnknownEffect(Schema.Tuple([Schema.Struct({ id: UserId })]));

const makeAuthRepository = (db: DirectoryDatabase): AuthRepository["Service"] => {
  /**
   * Runs the statements as one D1 batch, which is a transaction: D1 has no interactive ones, so
   * `db.transaction` can't be used and a later statement can't depend on JavaScript reading an
   * earlier result. Returns each statement's rows.
   */
  const atomically = (statements: ReadonlyArray<Compilable>) =>
    db.$client.batch(
      statements.map((statement) => {
        const { sql: text, params } = statement.toSQL();
        return db.$client.unsafe(text, params);
      }),
    );

  return AuthRepository.of({
    saveChallenge: (nonceHash, expiresAt) =>
      guarded(db.insert(authChallenges).values({ nonceHash, expiresAt })).pipe(Effect.asVoid),

    consumeChallenge: (nonceHash, now) =>
      guarded(
        db
          .delete(authChallenges)
          .where(eq(authChallenges.nonceHash, nonceHash))
          .returning({ expiresAt: authChallenges.expiresAt }),
      ).pipe(Effect.map((deleted) => deleted.some(({ expiresAt }) => expiresAt > now))),

    createSession: (session) => {
      const userId = sql`(${db
        .select({ id: users.id })
        .from(users)
        .where(eq(users.appleSubject, session.appleSubject))})`;
      return guarded(
        atomically([
          db
            .insert(users)
            .values({
              id: session.candidateUserId,
              appleSubject: session.appleSubject,
              createdAt: session.createdAt,
            })
            .onConflictDoNothing({ target: users.appleSubject }),
          db.insert(devices).values({ id: session.deviceId, userId, createdAt: session.createdAt }),
          db.insert(sessions).values({
            tokenHash: session.sessionHash,
            deviceId: session.deviceId,
            createdAt: session.createdAt,
            expiresAt: session.expiresAt,
          }),
          db
            .select({ id: users.id })
            .from(users)
            .where(eq(users.appleSubject, session.appleSubject)),
        ]).pipe(
          Effect.flatMap((results) => decodeCreatedUser(results[3])),
          Effect.map(([user]) => user.id),
        ),
      );
    },

    findSession: (sessionHash, now) =>
      guarded(
        db
          .select({
            userId: devices.userId,
            deviceId: sessions.deviceId,
            expiresAt: sessions.expiresAt,
          })
          .from(sessions)
          .innerJoin(devices, eq(devices.id, sessions.deviceId))
          .where(eq(sessions.tokenHash, sessionHash))
          .pipe(
            Effect.flatMap(([row]) =>
              row === undefined || row.expiresAt <= now
                ? Effect.succeedNone
                : Effect.asSome(decodeSession(row)),
            ),
          ),
      ),

    extendSession: (sessionHash, expiresAt) =>
      guarded(
        db.update(sessions).set({ expiresAt }).where(eq(sessions.tokenHash, sessionHash)),
      ).pipe(Effect.asVoid),

    revokeSession: (sessionHash) =>
      guarded(
        db
          .delete(devices)
          .where(
            inArray(
              devices.id,
              db
                .select({ id: sessions.deviceId })
                .from(sessions)
                .where(eq(sessions.tokenHash, sessionHash)),
            ),
          ),
      ).pipe(Effect.asVoid),

    savePushToken: (deviceId, record) => {
      const { environment, kind, token, updatedAt } = record;
      return guarded(
        atomically([
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

    deleteExpired: (now) =>
      guarded(
        atomically([
          db
            .delete(devices)
            .where(
              inArray(
                devices.id,
                db
                  .select({ id: sessions.deviceId })
                  .from(sessions)
                  .where(lte(sessions.expiresAt, now)),
              ),
            ),
          db.delete(authChallenges).where(lte(authChallenges.expiresAt, now)),
        ]),
      ).pipe(Effect.asVoid),
  });
};

/** `AuthRepository` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const AuthRepositoryLive = (binding: D1Database): Layer.Layer<AuthRepository> =>
  Layer.effect(AuthRepository, Effect.map(openDirectoryDatabase(binding), makeAuthRepository));
