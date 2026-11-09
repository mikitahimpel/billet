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
 * Sessions slide on lookup. Never verifies an identity: `AuthService` hands it verified tokens.
 */
export class AuthEngine extends Context.Service<
  AuthEngine,
  {
    readonly signInAnonymous: Effect.Effect<IssuedSession, AuthUnavailable>;
    /** A new session for an existing user. Fails `AuthRejected` if the user is gone. */
    readonly startSession: (
      userId: UserId,
    ) => Effect.Effect<IssuedSession, AuthRejected | AuthUnavailable>;
    /** The user linked to this Apple ID, or a new one linked to it, and a session for them. */
    readonly signInWithApple: (
      apple: VerifiedApple,
    ) => Effect.Effect<IssuedSession, AuthUnavailable>;
    /** Keeps the user and all it owns. Another user's Apple ID is `in-use`. */
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
