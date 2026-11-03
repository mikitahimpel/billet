import { Effect, Layer, Redacted } from "effect";
import { SecureRandom, Signature } from "effect/crypto";
import { Jwk, Jwks, Jws } from "effect/jose";
import type { AccessConfig } from "../src/access.ts";

/** A made-up Access application, for tests only, with a made-up one for agents. */
export const testAccess = {
  teamDomain: "billet-test.cloudflareaccess.com",
  audience: "a".repeat(64),
  agentAudience: "c".repeat(64),
} satisfies AccessConfig;

/** A made-up service token's `common_name`, as Access sets it (the token's client id). */
export const testAgent = "0123456789abcdef.access";

export const cryptoLayer = Signature.layerWebCrypto.pipe(
  Layer.provide(SecureRandom.layerWebCrypto),
);

const generate = (kid: string) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const pair = yield* Jwk.generateKeyPair({ algorithm: "RS256", kid });
      return {
        privateKey: yield* Jwk.importPrivate(pair.privateKey, "RS256"),
        publicJwk: pair.publicKey,
      };
    }).pipe(Effect.provide(cryptoLayer)),
  );

/** The team's signing key, and one Access never published. */
export const teamKey = await generate("team-1");
export const strangerKey = await generate("team-1");

/** The team's published keys, in place of `/cdn-cgi/access/certs`. */
export const teamKeys: Layer.Layer<Jwks.Jwks> = Jwks.layerLocal({ keys: [teamKey.publicJwk] });

const now = () => Math.floor(Date.now() / 1000);

/** Claims as Access issues them for a person, with any field replaced or removed (`undefined`). */
export const accessClaims = (overrides: Record<string, unknown> = {}) => {
  const claims: Record<string, unknown> = {
    aud: [testAccess.audience],
    email: "owner@example.com",
    exp: now() + 300,
    iat: now() - 5,
    nbf: now() - 5,
    iss: `https://${testAccess.teamDomain}`,
    sub: "7335d417-61da-459d-899c-0a01c76a2f94",
    type: "app",
    ...overrides,
  };
  return Object.fromEntries(Object.entries(claims).filter(([, value]) => value !== undefined));
};

export const signAccess = (
  overrides: Record<string, unknown> = {},
  key: typeof teamKey = teamKey,
): Promise<string> =>
  Effect.runPromise(
    Jws.sign(
      new TextEncoder().encode(JSON.stringify(accessClaims(overrides))),
      key.privateKey,
    ).pipe(Effect.map(Redacted.value), Effect.provide(cryptoLayer)),
  );

/** Claims as Access issues them for a service token: a `common_name`, no email, an empty `sub`. */
const agentOverrides = (overrides: Record<string, unknown>) => ({
  aud: [testAccess.agentAudience],
  email: undefined,
  common_name: testAgent,
  sub: "",
  ...overrides,
});

export const signAgent = (overrides: Record<string, unknown> = {}): Promise<string> =>
  signAccess(agentOverrides(overrides));

const base64Url = (text: string) =>
  btoa(text).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");

/** A token with `alg: none`: well-formed, unsigned. */
export const unsignedAccess = () =>
  `${base64Url(JSON.stringify({ alg: "none", typ: "JWT" }))}.${base64Url(JSON.stringify(accessClaims()))}.`;
