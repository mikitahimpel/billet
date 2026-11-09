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

/** Per request: `Jwks` shares an in-flight fetch, and a request must not wait on another's I/O. */
const AppleKeys = Jwks.layerRemote({ url: appleKeysUrl }).pipe(
  // Only a malformed constant above can fail this.
  Layer.orDie,
  Layer.provide(AppleKeysClient),
);

export const AppleIdentityLive: Layer.Layer<IdentityVerifier> = AppleIdentityVerifier.pipe(
  Layer.provide(AppleKeys),
  Layer.provide(Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto))),
);
