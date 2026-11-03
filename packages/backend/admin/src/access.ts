import { Context, Data, Effect, Layer, Schema } from "effect";
import { Signature } from "effect/crypto";
import { Jwks, Jwt } from "effect/jose";

/** The header Cloudflare Access adds to every request it lets through to the origin. */
export const accessJwtHeader = "cf-access-jwt-assertion";

/**
 * Which Access application may reach the admin panel: the team domain
 * (`<team>.cloudflareaccess.com`) and the application's audience (AUD) tag. Both come from the
 * Worker's configuration, never from the request.
 */
export interface AccessConfig {
  readonly teamDomain: string;
  readonly audience: string;
}

const teamDomainPattern = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.cloudflareaccess\.com$/;
const audiencePattern = /^[a-f0-9]{64}$/;

/**
 * The configuration, or `undefined` when either value is missing or malformed. The admin panel
 * then refuses every request: it fails closed, never open.
 */
export const accessConfigOf = (
  teamDomain: string | undefined,
  audience: string | undefined,
): AccessConfig | undefined => {
  const team = teamDomain?.trim().toLowerCase() ?? "";
  const aud = audience?.trim().toLowerCase() ?? "";
  return teamDomainPattern.test(team) && audiencePattern.test(aud)
    ? { teamDomain: team, audience: aud }
    : undefined;
};

export const accessIssuer = ({ teamDomain }: AccessConfig) => `https://${teamDomain}`;
export const accessCertsUrl = ({ teamDomain }: AccessConfig) =>
  `https://${teamDomain}/cdn-cgi/access/certs`;

/** Who Access let in. Only a person (with an email) may use the panel; service tokens may not. */
export interface AdminIdentity {
  readonly email: string;
}

/** The request is not from someone Access let in for this application. `reason` is a fixed label. */
export class AccessDenied extends Data.TaggedError("AccessDenied")<{ readonly reason: string }> {}

const AccessClaims = Schema.Struct({
  email: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(320)),
});

export class AccessVerifier extends Context.Service<
  AccessVerifier,
  { readonly verify: (token: string | null) => Effect.Effect<AdminIdentity, AccessDenied> }
>()("@billet/backend-admin/AccessVerifier") {}

/**
 * Verifies the Access JWT against the team's signing keys (`Jwks`): RS256 only, issued by the
 * team domain, for this audience, not expired, not used before `nbf`, with an email. Anything
 * else, including a missing header or keys that can't be read, is `AccessDenied`.
 */
export const accessVerifierLayer = (
  config: AccessConfig,
): Layer.Layer<AccessVerifier, never, Jwks.Jwks | Signature.Signature> =>
  Layer.effect(
    AccessVerifier,
    Effect.gen(function* () {
      const context = yield* Effect.context<Jwks.Jwks | Signature.Signature>();
      return AccessVerifier.of({
        verify: (token) =>
          token === null || token === ""
            ? Effect.fail(new AccessDenied({ reason: "missing" }))
            : Jwt.verifyWithKeySet(AccessClaims, token, {
                algorithms: ["RS256"],
                issuer: accessIssuer(config),
                audience: config.audience,
                requiredClaims: ["iss", "aud", "exp"],
              }).pipe(
                Effect.provideContext(context),
                Effect.map(({ claims }) => ({ email: claims.email.toLowerCase() })),
                Effect.mapError((error) =>
                  error._tag === "JoseError"
                    ? new AccessDenied({ reason: error.reason._tag })
                    : new AccessDenied({ reason: "claims-invalid" }),
                ),
              ),
      });
    }),
  );

/** Refuses everyone. What the panel runs on when the Access configuration is missing. */
export const denyAll = Layer.succeed(AccessVerifier, {
  verify: () => Effect.fail(new AccessDenied({ reason: "not-configured" })),
});
