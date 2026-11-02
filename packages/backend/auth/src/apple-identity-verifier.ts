import { Effect, Layer, Schema } from "effect";
import { Signature } from "effect/crypto";
import { type JoseError, Jwks, Jwt } from "effect/jose";
import { AuthRejected, AuthUnavailable } from "./auth-error.ts";
import { IdentityVerifier } from "./identity-verifier.ts";

export const appleIssuer = "https://appleid.apple.com";
export const appleKeysUrl = "https://appleid.apple.com/auth/keys";
export const appleAudience = "com.mikitahimpel.billet";

/**
 * Literals are deliberate: `aud` must be exactly the bundle id, so an array that merely contains it
 * is refused, and `sub` and `nonce` must be present and non-empty.
 */
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
 * Verifies Apple identity tokens against the `Jwks` service. RS256 is the only accepted algorithm,
 * so `none`, HMAC and any other signature scheme fail before a key is looked up.
 *
 * `Jwks` carries the key-rotation policy: see `layerRemote` in the platform package.
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
