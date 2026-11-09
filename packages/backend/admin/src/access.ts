import { Context, Data, Effect, Layer, Schema } from "effect";
import { Signature } from "effect/crypto";
import { Jwks, Jwt } from "effect/jose";

/** The header Cloudflare Access adds to every request it lets through to the origin. */
export const accessJwtHeader = "cf-access-jwt-assertion";

/**
 * From the Worker's config, never the request. Without `agentAudience`, no service token passes.
 */
export interface AccessConfig {
  readonly teamDomain: string;
  readonly audience: string;
  readonly agentAudience?: string | undefined;
}

const teamDomainPattern = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.cloudflareaccess\.com$/;
const audiencePattern = /^[a-f0-9]{64}$/;

/**
 * `undefined` when the team domain or panel AUD is missing or malformed: the panel fails closed.
 */
export const accessConfigOf = (
  teamDomain: string | undefined,
  audience: string | undefined,
  agentAudience?: string | undefined,
): AccessConfig | undefined => {
  const team = teamDomain?.trim().toLowerCase() ?? "";
  const aud = audience?.trim().toLowerCase() ?? "";
  const agentAud = agentAudience?.trim().toLowerCase() ?? "";
  if (!teamDomainPattern.test(team) || !audiencePattern.test(aud)) return undefined;
  return {
    teamDomain: team,
    audience: aud,
    agentAudience: audiencePattern.test(agentAud) ? agentAud : undefined,
  };
};

export const accessIssuer = ({ teamDomain }: AccessConfig) => `https://${teamDomain}`;
export const accessCertsUrl = ({ teamDomain }: AccessConfig) =>
  `https://${teamDomain}/cdn-cgi/access/certs`;

/** A person Access let in. Only a person may use the panel and make changes. */
export interface AdminIdentity {
  readonly email: string;
}

/** A person may use the panel; an agent (service token) may only read `/admin/api/agent`. */
export type AccessIdentity =
  | ({ readonly kind: "person" } & AdminIdentity)
  | { readonly kind: "agent"; readonly commonName: string };

/** The request is not from someone Access let in for this application. `reason` is a fixed label. */
export class AccessDenied extends Data.TaggedError("AccessDenied")<{ readonly reason: string }> {}

const AccessClaims = Schema.Struct({
  aud: Schema.Union([Schema.String, Schema.Array(Schema.String)]),
  email: Schema.optional(Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(320))),
  common_name: Schema.optional(Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(200))),
});

type AccessClaims = typeof AccessClaims.Type;

const identityOf = (
  claims: AccessClaims,
  config: AccessConfig,
): Effect.Effect<AccessIdentity, AccessDenied> => {
  const audiences = typeof claims.aud === "string" ? [claims.aud] : claims.aud;
  if (claims.email !== undefined) {
    return audiences.includes(config.audience)
      ? Effect.succeed({ kind: "person", email: claims.email.toLowerCase() })
      : Effect.fail(new AccessDenied({ reason: "person-audience" }));
  }
  if (claims.common_name !== undefined) {
    return config.agentAudience !== undefined && audiences.includes(config.agentAudience)
      ? Effect.succeed({ kind: "agent", commonName: claims.common_name })
      : Effect.fail(new AccessDenied({ reason: "agent-audience" }));
  }
  return Effect.fail(new AccessDenied({ reason: "no-identity" }));
};

export class AccessVerifier extends Context.Service<
  AccessVerifier,
  { readonly verify: (token: string | null) => Effect.Effect<AccessIdentity, AccessDenied> }
>()("@billet/backend-admin/AccessVerifier") {}

/**
 * RS256 only. A token with an email needs the panel audience; a `common_name` one, the agents'.
 */
export const accessVerifierLayer = (
  config: AccessConfig,
): Layer.Layer<AccessVerifier, never, Jwks.Jwks | Signature.Signature> =>
  Layer.effect(
    AccessVerifier,
    Effect.gen(function* () {
      const context = yield* Effect.context<Jwks.Jwks | Signature.Signature>();
      const audiences = [config.audience, config.agentAudience].filter(
        (audience): audience is string => audience !== undefined,
      );
      return AccessVerifier.of({
        verify: (token) =>
          token === null || token === ""
            ? Effect.fail(new AccessDenied({ reason: "missing" }))
            : Jwt.verifyWithKeySet(AccessClaims, token, {
                algorithms: ["RS256"],
                issuer: accessIssuer(config),
                audience: audiences,
                requiredClaims: ["iss", "aud", "exp"],
              }).pipe(
                Effect.provideContext(context),
                Effect.mapError((error) =>
                  error._tag === "JoseError"
                    ? new AccessDenied({ reason: error.reason._tag })
                    : new AccessDenied({ reason: "claims-invalid" }),
                ),
                Effect.flatMap(({ claims }) => identityOf(claims, config)),
              ),
      });
    }),
  );

/** Refuses everyone. What the panel runs on when the Access configuration is missing. */
export const denyAll = Layer.succeed(AccessVerifier, {
  verify: () => Effect.fail(new AccessDenied({ reason: "not-configured" })),
});
