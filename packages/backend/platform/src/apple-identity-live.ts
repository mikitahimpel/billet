import { Layer } from "effect";
import { SecureRandom, Signature } from "effect/crypto";
import { FetchHttpClient } from "effect/http";
import { Jwks } from "effect/jose";
import { AppleIdentityVerifier, appleKeysUrl } from "@billet/backend-auth/apple-identity-verifier";
import type { IdentityVerifier } from "@billet/backend-auth/identity-verifier";

// `Jwks` refuses any response from another URL, and manual redirects stop the request being sent.
const AppleKeysClient = FetchHttpClient.layer.pipe(
  Layer.provide(Layer.succeed(FetchHttpClient.RequestInit, { redirect: "manual" })),
);

/**
 * Apple's keys, cached per isolate. The defaults are the policy: keys are reused for 10 minutes and
 * refetched once for an unknown `kid`, at most every 30 seconds, so rotation is picked up and random
 * `kid`s can't drive traffic to Apple. A failed or slow (over 5 seconds) fetch fails the sign-in,
 * and an expired key set is never used.
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
