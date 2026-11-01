import { Context, type Effect, type Option } from "effect";
import type { DeviceId, EpochMillis, UserId } from "@billet/contracts-domain/ids";
import type {
  ApnsEnvironment,
  PushToken,
  PushTokenKind,
} from "@billet/contracts-domain/push-token";
import type { AuthUnavailable } from "./auth-error.ts";

/** Lowercase hex SHA-256. Raw nonces and session tokens never reach the repository. */
export type TokenHash = string;

export interface NewSession {
  readonly appleSubject: string;
  /** Used only when this subject has no user yet. */
  readonly candidateUserId: UserId;
  readonly deviceId: DeviceId;
  readonly sessionHash: TokenHash;
  readonly createdAt: EpochMillis;
  readonly expiresAt: EpochMillis;
}

export interface SessionRecord {
  readonly userId: UserId;
  readonly deviceId: DeviceId;
  readonly expiresAt: EpochMillis;
}

export interface PushTokenRecord {
  readonly kind: PushTokenKind;
  readonly environment: ApnsEnvironment;
  readonly token: PushToken;
  readonly updatedAt: EpochMillis;
}

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
    /** Deletes the session and its device's push tokens, so a signed-out phone gets no notes. */
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
    /** Removes expired challenges, expired sessions and those sessions' push tokens. */
    readonly deleteExpired: (now: EpochMillis) => Effect.Effect<void, AuthUnavailable>;
  }
>()("@billet/backend-auth/AuthRepository") {}
