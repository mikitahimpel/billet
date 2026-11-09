import { Effect, Layer, Schema } from "effect";
import { Signature } from "effect/crypto";
import { type JoseError, Jwks, Jwt } from "effect/jose";
import { AuthRejected, AuthUnavailable } from "./auth-error.ts";
import { IdentityVerifier } from "./identity-verifier.ts";

export const appleIssuer = "https://appleid.apple.com";
export const appleKeysUrl = "https://appleid.apple.com/auth/keys";
export const appleAudience = "com.mikitahimpel.billet";

/** Literals are deliberate: an `aud` array that merely contains the bundle id is refused. */
const AppleClaims = Schema.Struct({
  iss: Schema.Literal(appleIssuer),
  aud: Schema.Literal(appleAudience),
  sub: Schema.String.check(Schema.isNonEmpty()),
  nonce: Schema.String.check(Schema.isNonEmpty()),
});

const fromJoseError = (error: JoseError.JoseError): AuthRejected | AuthUnavailable => {
  const { reason } = error;
  switch (reason._tag) {
    case "KeySetUnavailable":
      return new AuthUnavailable({ reason: "apple-keys-unavailable" });
    case "ClaimValidationFailed":
      return new AuthRejected({ reason: `claim-${reason.claim}-${reason.reason}` });
    default:
      return new AuthRejected({ reason: reason._tag });
  }
};

/**
 * RS256 only, so `none`, HMAC and other schemes fail before a key is looked up.
 */
export const AppleIdentityVerifier: Layer.Layer<
  IdentityVerifier,
  never,
  Jwks.Jwks | Signature.Signature
> = Layer.effect(
  IdentityVerifier,
  Effect.gen(function* () {
    const context = yield* Effect.context<Jwks.Jwks | Signature.Signature>();
    return IdentityVerifier.of({
      verify: (identityToken) =>
        Jwt.verifyWithKeySet(AppleClaims, identityToken, {
          algorithms: ["RS256"],
          issuer: appleIssuer,
          audience: appleAudience,
          requiredClaims: ["iss", "aud", "exp", "sub"],
        }).pipe(
          Effect.provideContext(context),
          Effect.map(({ claims }) => ({ subject: claims.sub, nonce: claims.nonce })),
          Effect.mapError((error) =>
            error._tag === "JoseError"
              ? fromJoseError(error)
              : new AuthRejected({ reason: "claims-invalid" }),
          ),
        ),
    });
  }),
);
