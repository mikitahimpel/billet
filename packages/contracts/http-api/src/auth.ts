import { Schema } from "effect";
import { DeviceId, EpochMillis, UserId } from "@billet/contracts-domain/ids";

/** 32 random bytes, base64url without padding. */
const opaqueValue = /^[A-Za-z0-9_-]{43}$/;

/** One-time; the client passes it as `ASAuthorizationAppleIDRequest.nonce` for Apple to sign. */
export const AuthNonce = Schema.String.check(Schema.isPattern(opaqueValue)).pipe(
  Schema.brand("AuthNonce"),
);
export type AuthNonce = typeof AuthNonce.Type;

/** Only its hash is stored, never logged. Pre-Better Auth tokens are 43 chars, later ones 32. */
export const SessionToken = Schema.String.check(
  Schema.isPattern(/^[A-Za-z0-9_-]{32}(?:[A-Za-z0-9_-]{11})?$/),
).pipe(Schema.brand("SessionToken"));

/**
 * The anonymous account. In the iCloud Keychain so other phones share it; the server stores a hash.
 */
export const AccountKey = Schema.String.check(Schema.isPattern(opaqueValue)).pipe(
  Schema.brand("AccountKey"),
);
export type AccountKey = typeof AccountKey.Type;
export type SessionToken = typeof SessionToken.Type;

/** An Apple identity token. The cap is checked before any cryptography runs. */
export const IdentityToken = Schema.String.check(
  Schema.isNonEmpty(),
  Schema.isMaxLength(8192),
).pipe(Schema.brand("IdentityToken"));
export type IdentityToken = typeof IdentityToken.Type;

export const AuthChallengeResponse = Schema.Struct({ nonce: AuthNonce, expiresAt: EpochMillis });
export type AuthChallengeResponse = typeof AuthChallengeResponse.Type;

export const SignInWithAppleRequest = Schema.Struct({ identityToken: IdentityToken });
export type SignInWithAppleRequest = typeof SignInWithAppleRequest.Type;

/** Signs in to the account this key opened, and opens one the first time a key is seen. */
export const SignInAnonymouslyRequest = Schema.Struct({ accountKey: AccountKey });
export type SignInAnonymouslyRequest = typeof SignInAnonymouslyRequest.Type;

export const SessionResponse = Schema.Struct({
  sessionToken: SessionToken,
  expiresAt: EpochMillis,
  userId: UserId,
  deviceId: DeviceId,
});
export type SessionResponse = typeof SessionResponse.Type;
