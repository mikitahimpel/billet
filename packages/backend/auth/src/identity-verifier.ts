import { Context, type Effect, type Redacted } from "effect";
import type { AuthRejected, AuthUnavailable } from "./auth-error.ts";

export interface VerifiedIdentity {
  /** Apple's stable user id for this team. */
  readonly subject: string;
  /** The nonce Apple signed into the token. Still has to be checked against the issued ones. */
  readonly nonce: string;
}

/** Proves who signed in. Fails closed: anything short of a full verification is an error. */
export class IdentityVerifier extends Context.Service<
  IdentityVerifier,
  {
    readonly verify: (
      identityToken: Redacted.Redacted<string>,
    ) => Effect.Effect<VerifiedIdentity, AuthRejected | AuthUnavailable>;
  }
>()("@billet/backend-auth/IdentityVerifier") {}
