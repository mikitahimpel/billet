import { Context, type Effect, type Option, Schema } from "effect";
import { DeviceId, EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { ApnsEnvironment, PushToken, PushTokenKind } from "@billet/contracts-domain/push-token";
import type { AuthUnavailable } from "./auth-error.ts";

/** Lowercase hex SHA-256. Raw nonces, account keys and session tokens are never stored. */
export const TokenHash = Schema.String.check(Schema.isNonEmpty());
export type TokenHash = typeof TokenHash.Type;

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
  createdAt: EpochMillis,
});

export const StoredDevice = Schema.Struct({
  id: DeviceId,
  userId: UserId,
  createdAt: EpochMillis,
});

export const StoredChallenge = Schema.Struct({
  nonceHash: TokenHash,
  expiresAt: EpochMillis,
});

export const StoredAccountKey = Schema.Struct({
  keyHash: TokenHash,
  userId: UserId,
  createdAt: EpochMillis,
});

export const StoredPushToken = Schema.Struct({
  ...PushTokenRecord.fields,
  deviceId: DeviceId,
});

/**
 * Persistence for sign-in challenges, account keys and the device registry. Users and sessions
 * belong to `AuthEngine`. Each method is one atomic operation, so an implementation maps it to one
 * Drizzle statement or transaction. Methods have no service requirements (the Layer captures the
 * database) and every storage failure is `AuthUnavailable`. `test/auth-repository-contract.ts` is
 * the behaviour any implementation must pass.
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
    /** The user this account key opened, if any. */
    readonly findAccountKey: (
      keyHash: TokenHash,
    ) => Effect.Effect<Option.Option<UserId>, AuthUnavailable>;
    /**
     * Records that this key opened this user. A key is held by one user forever, so when two first
     * sign-ins race on one key, only one sees `true`.
     */
    readonly saveAccountKey: (
      keyHash: TokenHash,
      userId: UserId,
      createdAt: EpochMillis,
    ) => Effect.Effect<boolean, AuthUnavailable>;
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
