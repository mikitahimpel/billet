import { Effect, Exit, Layer, Redacted } from "effect";
import { SecureRandom, Signature } from "effect/crypto";
import { FetchHttpClient } from "effect/http";
import { Jwk, Jws } from "effect/jose";
import { describe, expect, it } from "vitest";
import {
  appleAudience,
  appleIssuer,
  appleKeysUrl,
} from "@billet/backend-auth/apple-identity-verifier";
import { IdentityVerifier } from "@billet/backend-auth/identity-verifier";
import { AppleIdentityLive } from "../src/apple-identity-live.ts";

const cryptoLayer = Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto));

const signed = Effect.gen(function* () {
  const pair = yield* Jwk.generateKeyPair({ algorithm: "RS256", kid: "apple-1" });
  const privateKey = yield* Jwk.importPrivate(pair.privateKey, "RS256");
  const claims = {
    iss: appleIssuer,
    aud: appleAudience,
    sub: "subject",
    nonce: "nonce",
    exp: Math.floor(Date.now() / 1000) + 300,
  };
  const token = yield* Jws.sign(new TextEncoder().encode(JSON.stringify(claims)), privateKey);
  return { token, publicJwk: pair.publicKey };
}).pipe(Effect.provide(cryptoLayer));

const verifyWith = (fetch: typeof globalThis.fetch, token: Redacted.Redacted<string>) =>
  Effect.runPromiseExit(
    Effect.gen(function* () {
      const verifier = yield* IdentityVerifier;
      return yield* verifier.verify(token);
    }).pipe(Effect.provide(AppleIdentityLive), Effect.provideService(FetchHttpClient.Fetch, fetch)),
  );

describe("AppleIdentityLive", () => {
  it("reads Apple's key URL without following redirects, cached only on success", async () => {
    const { token, publicJwk } = await Effect.runPromise(signed);
    const requests: Array<{ url: string; init: RequestInit | undefined }> = [];
    const fetch: typeof globalThis.fetch = (input, init) => {
      requests.push({ url: String(input), init });
      return Promise.resolve(Response.json({ keys: [publicJwk] }));
    };
    const exit = await verifyWith(fetch, token);
    expect(exit).toEqual(Exit.succeed({ subject: "subject", nonce: "nonce" }));
    expect(requests.map(({ url }) => url)).toEqual([appleKeysUrl]);
    expect(requests[0]?.init).toMatchObject({
      redirect: "manual",
      cf: { cacheEverything: true, cacheTtlByStatus: { "200-299": 600, "300-599": 0 } },
    });
  });

  it("issues nothing when the fetch fails", async () => {
    const { token } = await Effect.runPromise(signed);
    const exit = await verifyWith(() => Promise.reject(new Error("offline")), token);
    expect(Exit.isFailure(exit)).toBe(true);
    expect(JSON.stringify(exit)).toContain("apple-keys-unavailable");
  });
});
