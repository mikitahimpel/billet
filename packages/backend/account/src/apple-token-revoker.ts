import { Context, Effect, Layer, type Redacted } from "effect";

/** What became of a revocation. Deleting an account never waits on it to succeed. */
export type RevokeOutcome = "revoked" | "not-configured" | "rejected" | "failed";

/**
 * Revokes the user's Sign in with Apple token through Apple's REST API, as Apple asks of an app
 * that deletes an account: trades a fresh authorization code for a token, then revokes it. The
 * code is single-use and never stored or logged.
 */
export class AppleTokenRevoker extends Context.Service<
  AppleTokenRevoker,
  {
    readonly revoke: (authorizationCode: Redacted.Redacted<string>) => Effect.Effect<RevokeOutcome>;
  }
>()("@billet/backend-account/AppleTokenRevoker") {
  /** Has no key to sign with. For tests and for a Worker without the secret. */
  static readonly unconfigured = Layer.succeed(AppleTokenRevoker, {
    revoke: () => Effect.succeed("not-configured" as const),
  });
}
