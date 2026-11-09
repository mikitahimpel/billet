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
 * Atomic per method; users and sessions belong to `AuthEngine`. See auth-repository-contract.ts.
 */
export class AuthRepository extends Context.Service<
  AuthRepository,
  {
    readonly saveChallenge: (
      nonceHash: TokenHash,
      expiresAt: EpochMillis,
    ) => Effect.Effect<void, AuthUnavailable>;
    /** Reports whether it was live. One atomic delete: of concurrent uses only one sees `true`. */
    readonly consumeChallenge: (
      nonceHash: TokenHash,
      now: EpochMillis,
    ) => Effect.Effect<boolean, AuthUnavailable>;
    readonly findAccountKey: (
      keyHash: TokenHash,
    ) => Effect.Effect<Option.Option<UserId>, AuthUnavailable>;
    /** A key belongs to one user forever: of two racing first sign-ins only one sees `true`. */
    readonly saveAccountKey: (
      keyHash: TokenHash,
      userId: UserId,
      createdAt: EpochMillis,
    ) => Effect.Effect<boolean, AuthUnavailable>;
    /** A token held by another device moves here: APNs tokens identify the install. */
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
