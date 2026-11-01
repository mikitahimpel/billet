import { Context, type Effect, type Option, Schema } from "effect";
import { DeviceId, EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { ApnsEnvironment, PushToken, PushTokenKind } from "@billet/contracts-domain/push-token";
import type { AuthUnavailable } from "./auth-error.ts";

/** Lowercase hex SHA-256. Raw nonces and session tokens never reach the repository. */
export const TokenHash = Schema.String.check(Schema.isNonEmpty());
export type TokenHash = typeof TokenHash.Type;

export interface NewSession {
  readonly appleSubject: string;
  /** Used only when this subject has no user yet. */
  readonly candidateUserId: UserId;
  readonly deviceId: DeviceId;
  readonly sessionHash: TokenHash;
  readonly createdAt: EpochMillis;
  readonly expiresAt: EpochMillis;
}

export const SessionRecord = Schema.Struct({
  userId: UserId,
  deviceId: DeviceId,
  expiresAt: EpochMillis,
});
export type SessionRecord = typeof SessionRecord.Type;

export const PushTokenRecord = Schema.Struct({
  kind: PushTokenKind,
  environment: ApnsEnvironment,
  token: PushToken,
  updatedAt: EpochMillis,
});
export type PushTokenRecord = typeof PushTokenRecord.Type;

/** What each stored table holds. A test in `platform` fails if a table's columns differ. */
export const StoredUser = Schema.Struct({
  id: UserId,
  appleSubject: Schema.String.check(Schema.isNonEmpty()),
  createdAt: EpochMillis,
});

export const StoredDevice = Schema.Struct({
  id: DeviceId,
  userId: UserId,
  createdAt: EpochMillis,
});

export const StoredSession = Schema.Struct({
  tokenHash: TokenHash,
  deviceId: DeviceId,
  createdAt: EpochMillis,
  expiresAt: EpochMillis,
});

export const StoredChallenge = Schema.Struct({
  nonceHash: TokenHash,
  expiresAt: EpochMillis,
});

export const StoredPushToken = Schema.Struct({
  ...PushTokenRecord.fields,
  deviceId: DeviceId,
});

/**
 * Persistence for sign-in, sessions and the device registry. Each method is one atomic operation,
 * so an implementation maps it to one Drizzle statement or transaction. Methods have no service
 * requirements (the Layer captures the database) and every storage failure is `AuthUnavailable`.
 * `test/auth-repository-contract.ts` is the behaviour any implementation must pass.
 */
export class AuthRepository extends Context.Service<
  AuthRepository,
  {
    readonly saveChallenge: (
      nonceHash: TokenHash,
      expiresAt: EpochMillis,
    ) => Effect.Effect<void, AuthUnavailable>;
    /**
     * Deletes the challenge and reports whether it was live. Must be a single atomic delete, so that
     * of two concurrent sign-ins with one nonce, only one sees `true`.
     */
    readonly consumeChallenge: (
      nonceHash: TokenHash,
      now: EpochMillis,
    ) => Effect.Effect<boolean, AuthUnavailable>;
    /** Finds or creates the user, then creates the device and its session, all or nothing. */
    readonly createSession: (session: NewSession) => Effect.Effect<UserId, AuthUnavailable>;
    /** Looks up by hash and returns only a session that has not expired. */
    readonly findSession: (
      sessionHash: TokenHash,
      now: EpochMillis,
    ) => Effect.Effect<Option.Option<SessionRecord>, AuthUnavailable>;
    readonly extendSession: (
      sessionHash: TokenHash,
      expiresAt: EpochMillis,
    ) => Effect.Effect<void, AuthUnavailable>;
    /**
     * Deletes the session, its device and that device's push tokens, so a signed-out phone gets no
     * notes. Device ids are issued per sign-in, so nothing can reach the device again.
     */
    readonly revokeSession: (sessionHash: TokenHash) => Effect.Effect<void, AuthUnavailable>;
    /**
     * Sets the device's token of this kind, replacing any earlier one. A token already held by
     * another device moves here: APNs tokens identify the install, so the latest sign-in owns it.
     */
    readonly savePushToken: (
      deviceId: DeviceId,
      record: PushTokenRecord,
    ) => Effect.Effect<void, AuthUnavailable>;
    readonly listPushTokens: (
      deviceId: DeviceId,
    ) => Effect.Effect<ReadonlyArray<PushTokenRecord>, AuthUnavailable>;
    /** Removes expired challenges, and expired sessions with their devices and push tokens. */
    readonly deleteExpired: (now: EpochMillis) => Effect.Effect<void, AuthUnavailable>;
  }
>()("@billet/backend-auth/AuthRepository") {}
