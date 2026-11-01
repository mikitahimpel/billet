import { Layer } from "effect";
import { SecureRandom, Signature } from "effect/crypto";
import { FetchHttpClient } from "effect/http";
import { Jwks } from "effect/jose";
import { AppleIdentityVerifier, appleKeysUrl } from "@billet/backend-auth/apple-identity-verifier";
import type { IdentityVerifier } from "@billet/backend-auth/identity-verifier";

// `Jwks` refuses any response from another URL, and manual redirects stop the request being sent.
// Only successful responses reach Cloudflare's cache, so a failure at Apple's end is never replayed.
const AppleKeysClient = FetchHttpClient.layer.pipe(
  Layer.provide(
    Layer.succeed(FetchHttpClient.RequestInit, {
      redirect: "manual",
      cf: { cacheEverything: true, cacheTtlByStatus: { "200-299": 600, "300-599": 0 } },
    }),
  ),
);

/**
 * Build this once per request. `Jwks` shares one in-flight fetch between its callers, and a Worker
 * request must not wait on I/O started by another, so the layer can't outlive a request. The key
 * cache is therefore Cloudflare's, shared across requests through the subrequest: forged tokens
 * can't drive traffic to Apple, and a rotated key is picked up within 10 minutes. A failed or slow
 * (over 5 seconds) fetch fails the sign-in, and an expired key set is never used.
 */
const AppleKeys = Jwks.layerRemote({ url: appleKeysUrl }).pipe(
  // Only a malformed constant above can fail this.
  Layer.orDie,
  Layer.provide(AppleKeysClient),
);

/** The real `IdentityVerifier`, on `fetch` and Web Crypto. */
export const AppleIdentityLive: Layer.Layer<IdentityVerifier> = AppleIdentityVerifier.pipe(
  Layer.provide(AppleKeys),
  Layer.provide(Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto))),
);
