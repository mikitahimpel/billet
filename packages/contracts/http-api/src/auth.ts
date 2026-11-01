import { Schema } from "effect";
import { DeviceId, EpochMillis, UserId } from "@billet/contracts-domain/ids";

/** 32 random bytes, base64url without padding. */
const opaqueValue = /^[A-Za-z0-9_-]{43}$/;

/**
 * One-time sign-in nonce issued by the server. The client passes it unchanged as
 * `ASAuthorizationAppleIDRequest.nonce`, so Apple signs it into the identity token.
 */
export const AuthNonce = Schema.String.check(Schema.isPattern(opaqueValue)).pipe(
  Schema.brand("AuthNonce"),
);
export type AuthNonce = typeof AuthNonce.Type;

/** The opaque bearer credential. The server keeps only its hash, and it is never logged. */
export const SessionToken = Schema.String.check(Schema.isPattern(opaqueValue)).pipe(
  Schema.brand("SessionToken"),
);
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

export const SessionResponse = Schema.Struct({
  sessionToken: SessionToken,
  expiresAt: EpochMillis,
  userId: UserId,
  deviceId: DeviceId,
});
export type SessionResponse = typeof SessionResponse.Type;
