import { Context, type Effect, type Option, type Redacted } from "effect";
import type { DeviceId, EpochMillis, UserId } from "@billet/contracts-domain/ids";
import type { SessionToken } from "@billet/contracts-http-api/auth";
import type { AuthRejected, AuthUnavailable } from "./auth-error.ts";
import type { TokenHash } from "./auth-repository.ts";

/** A new session on a new device. The token goes to the client once and is stored only hashed. */
export interface IssuedSession {
  readonly sessionToken: SessionToken;
  readonly userId: UserId;
  readonly deviceId: DeviceId;
  readonly expiresAt: EpochMillis;
}

export interface LiveSession {
  readonly userId: UserId;
  readonly deviceId: DeviceId;
  /** The account can be recovered with Sign in with Apple. */
  readonly linked: boolean;
}

/** An Apple identity token that `IdentityVerifier` accepted and whose nonce was live. */
export interface VerifiedApple {
  readonly identityToken: Redacted.Redacted<string>;
  readonly subject: string;
  readonly nonce: string;
}

export type LinkOutcome = "linked" | "in-use";

/**
 * Users, sessions and linked identities (Better Auth in the platform package). Each session has its
 * own device, which push tokens hang off. Sessions slide: each lookup may push the expiry out.
 * Every storage failure is `AuthUnavailable`. It never verifies an identity itself: `AuthService`
 * hands it only tokens it has verified.
 */
export class AuthEngine extends Context.Service<
  AuthEngine,
  {
    /** Opens a new anonymous user and a session for it. */
    readonly signInAnonymous: Effect.Effect<IssuedSession, AuthUnavailable>;
    /** A new session for an existing user. Fails `AuthRejected` if the user is gone. */
    readonly startSession: (
      userId: UserId,
    ) => Effect.Effect<IssuedSession, AuthRejected | AuthUnavailable>;
    /** The user linked to this Apple ID, or a new one linked to it, and a session for them. */
    readonly signInWithApple: (
      apple: VerifiedApple,
    ) => Effect.Effect<IssuedSession, AuthUnavailable>;
    /**
     * Links the session's user to this Apple ID, keeping the user and everything it owns. Linking an
     * Apple ID the user already has is `linked`; one that belongs to another user is `in-use`.
     */
    readonly linkApple: (
      sessionToken: Redacted.Redacted<string>,
      apple: VerifiedApple,
    ) => Effect.Effect<LinkOutcome, AuthRejected | AuthUnavailable>;
    readonly findSession: (
      sessionToken: Redacted.Redacted<string>,
    ) => Effect.Effect<Option.Option<LiveSession>, AuthUnavailable>;
    /** Ends the session and forgets its device with its push tokens. */
    readonly endSession: (sessionHash: TokenHash) => Effect.Effect<void, AuthUnavailable>;
  }
>()("@billet/backend-auth/AuthEngine") {}
