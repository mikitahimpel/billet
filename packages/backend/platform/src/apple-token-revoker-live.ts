import { Effect, Layer, Redacted } from "effect";
import { AppleTokenRevoker, type RevokeOutcome } from "@billet/backend-account/apple-token-revoker";
import { appleAudience } from "@billet/backend-auth/apple-identity-verifier";
import { appleTeamId, signEs256 } from "./es256-jwt.ts";
import { spanMethods } from "@billet/backend-observability/span-methods";

const appleOrigin = "https://appleid.apple.com";
/** Apple accepts a client secret for up to six months; this one lives for one request. */
const secretLifetimeSeconds = 300;
const requestTimeoutMillis = 5000;

export interface SignInWithAppleKey {
  /** The Sign in with Apple key, PKCS #8 PEM. */
  readonly pem: Redacted.Redacted<string>;
  readonly keyId: Redacted.Redacted<string>;
}

export type AppleFetch = (url: string, init: RequestInit) => Promise<Response>;

const form = (fields: Readonly<Record<string, string>>): RequestInit => ({
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams(fields).toString(),
  redirect: "manual",
  signal: AbortSignal.timeout(requestTimeoutMillis),
});

const refreshTokenOf = (body: unknown): string | undefined => {
  const token = (body as { refresh_token?: unknown } | null)?.refresh_token;
  return typeof token === "string" && token.length > 0 ? token : undefined;
};

/**
 * Trades the code for a refresh token at `/auth/token`, then revokes that token at `/auth/revoke`.
 * Revoking the refresh token ends the app's authorization for this Apple ID. Nothing from either
 * response or from a failure is logged: they carry the code, tokens or the user's identity.
 */
export const revokeAppleToken = async (
  key: SignInWithAppleKey,
  code: Redacted.Redacted<string>,
  send: AppleFetch = fetch,
): Promise<RevokeOutcome> => {
  const now = Math.floor(Date.now() / 1000);
  const clientSecret = await signEs256(
    { pem: Redacted.value(key.pem), keyId: Redacted.value(key.keyId) },
    {
      iss: appleTeamId,
      iat: now,
      exp: now + secretLifetimeSeconds,
      aud: appleOrigin,
      sub: appleAudience,
    },
  );
  const client = { client_id: appleAudience, client_secret: clientSecret };

  const exchanged = await send(
    `${appleOrigin}/auth/token`,
    form({ ...client, code: Redacted.value(code), grant_type: "authorization_code" }),
  );
  if (!exchanged.ok) return "rejected";
  const refreshToken = refreshTokenOf(await exchanged.json());
  if (refreshToken === undefined) return "rejected";

  const revoked = await send(
    `${appleOrigin}/auth/revoke`,
    form({ ...client, token: refreshToken, token_type_hint: "refresh_token" }),
  );
  return revoked.ok ? "revoked" : "rejected";
};

/**
 * The real `AppleTokenRevoker`. Without the key (an empty secret) it revokes nothing, and says so.
 */
export const AppleTokenRevokerLive = (
  key: SignInWithAppleKey | undefined,
  send: AppleFetch = fetch,
): Layer.Layer<AppleTokenRevoker> =>
  Layer.succeed(
    AppleTokenRevoker,
    spanMethods("AppleTokenRevoker", {
      revoke: (code) =>
        key === undefined
          ? Effect.succeed("not-configured")
          : Effect.tryPromise(() => revokeAppleToken(key, code, send)).pipe(
              Effect.orElseSucceed((): RevokeOutcome => "failed"),
            ),
    }),
  );

/** The key from the Worker's secrets, if both are set. */
export const signInWithAppleKeyOf = (env: {
  readonly APPLE_SIGN_IN_KEY?: string;
  readonly APPLE_SIGN_IN_KEY_ID?: string;
}): SignInWithAppleKey | undefined =>
  env.APPLE_SIGN_IN_KEY === undefined ||
  env.APPLE_SIGN_IN_KEY === "" ||
  env.APPLE_SIGN_IN_KEY_ID === undefined ||
  env.APPLE_SIGN_IN_KEY_ID === ""
    ? undefined
    : {
        pem: Redacted.make(env.APPLE_SIGN_IN_KEY),
        keyId: Redacted.make(env.APPLE_SIGN_IN_KEY_ID),
      };
