import { Effect, Redacted } from "effect";
import { describe, expect, it } from "vitest";
import { AppleTokenRevoker } from "@billet/backend-account/apple-token-revoker";
import { appleAudience, legacyAppleAudience } from "@billet/backend-auth/apple-identity-verifier";
import {
  type AppleFetch,
  AppleTokenRevokerLive,
  revokeAppleToken,
  signInWithAppleKeyOf,
} from "../src/apple-token-revoker-live.ts";
import { appleTeamId } from "../src/es256-jwt.ts";

const keys = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
  "sign",
  "verify",
])) as CryptoKeyPair;
const der = new Uint8Array(
  (await crypto.subtle.exportKey("pkcs8", keys.privateKey)) as ArrayBuffer,
);
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
const key = { pem: Redacted.make(pem), keyId: Redacted.make("KEY123") };

const fromBase64Url = (text: string) =>
  Uint8Array.from(atob(text.replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0));

/** Apple, as far as the revoker sees it: each call is recorded and answered from `replies`. */
const fakeApple = (replies: ReadonlyArray<Response>) => {
  const calls: Array<{ url: string; fields: URLSearchParams }> = [];
  const send: AppleFetch = (url, init) => {
    calls.push({ url, fields: new URLSearchParams(String(init.body)) });
    return Promise.resolve(replies[calls.length - 1] ?? new Response(null, { status: 500 }));
  };
  return { calls, send };
};

describe("revoking a Sign in with Apple token", () => {
  it("trades the code for a refresh token and revokes it, with a signed client secret", async () => {
    const apple = fakeApple([
      Response.json({ access_token: "access", refresh_token: "refresh-1", id_token: "id" }),
      new Response(null, { status: 200 }),
    ]);
    expect(await revokeAppleToken(key, Redacted.make("code-1"), apple.send)).toBe("revoked");

    const [exchange, revoke] = apple.calls;
    expect(exchange?.url).toBe("https://appleid.apple.com/auth/token");
    expect(exchange?.fields.get("grant_type")).toBe("authorization_code");
    expect(exchange?.fields.get("code")).toBe("code-1");
    expect(exchange?.fields.get("client_id")).toBe(appleAudience);
    expect(revoke?.url).toBe("https://appleid.apple.com/auth/revoke");
    expect(revoke?.fields.get("token")).toBe("refresh-1");
    expect(revoke?.fields.get("token_type_hint")).toBe("refresh_token");

    const secret = exchange?.fields.get("client_secret") ?? "";
    const [header = "", payload = "", signature = ""] = secret.split(".");
    expect(JSON.parse(new TextDecoder().decode(fromBase64Url(header)))).toEqual({
      alg: "ES256",
      kid: "KEY123",
    });
    const claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payload)));
    expect(claims).toMatchObject({
      iss: appleTeamId,
      aud: "https://appleid.apple.com",
      sub: appleAudience,
    });
    expect(claims.exp - claims.iat).toBeLessThanOrEqual(300);
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      keys.publicKey,
      fromBase64Url(signature),
      new TextEncoder().encode(`${header}.${payload}`),
    );
    expect(valid).toBe(true);
  });

  it("stops at a code refused for every bundle id, and revokes nothing", async () => {
    const refused = () => Response.json({ error: "invalid_grant" }, { status: 400 });
    const apple = fakeApple([refused(), refused()]);
    expect(await revokeAppleToken(key, Redacted.make("stale"), apple.send)).toBe("rejected");
    expect(apple.calls.map(({ url }) => url)).toEqual([
      "https://appleid.apple.com/auth/token",
      "https://appleid.apple.com/auth/token",
    ]);
  });

  it("redeems a code from the first app under its bundle id", async () => {
    const apple = fakeApple([
      Response.json({ error: "invalid_client" }, { status: 400 }),
      Response.json({ refresh_token: "refresh-old" }),
      new Response(null, { status: 200 }),
    ]);
    expect(await revokeAppleToken(key, Redacted.make("code-old"), apple.send)).toBe("revoked");
    const [first, second, revoke] = apple.calls;
    expect(first?.fields.get("client_id")).toBe(appleAudience);
    expect(second?.fields.get("client_id")).toBe(legacyAppleAudience);
    expect(revoke?.url).toBe("https://appleid.apple.com/auth/revoke");
    expect(revoke?.fields.get("client_id")).toBe(legacyAppleAudience);
    expect(revoke?.fields.get("token")).toBe("refresh-old");
  });

  it("says so when Apple refuses the revocation", async () => {
    const apple = fakeApple([
      Response.json({ refresh_token: "refresh-1" }),
      Response.json({ error: "invalid_client" }, { status: 400 }),
    ]);
    expect(await revokeAppleToken(key, Redacted.make("code"), apple.send)).toBe("rejected");
  });

  it("never fails the deletion: no key, a broken key or a network failure is an outcome", async () => {
    const revoke = (layer: ReturnType<typeof AppleTokenRevokerLive>) =>
      Effect.runPromise(
        AppleTokenRevoker.use((revoker) => revoker.revoke(Redacted.make("code"))).pipe(
          Effect.provide(layer),
        ),
      );
    expect(await revoke(AppleTokenRevokerLive(undefined))).toBe("not-configured");
    expect(
      await revoke(AppleTokenRevokerLive({ pem: Redacted.make("not a key"), keyId: key.keyId })),
    ).toBe("failed");
    expect(
      await revoke(AppleTokenRevokerLive(key, () => Promise.reject(new Error("offline")))),
    ).toBe("failed");
  });

  it("reads the key from the Worker's secrets only when both are set", () => {
    expect(signInWithAppleKeyOf({})).toBeUndefined();
    expect(
      signInWithAppleKeyOf({ APPLE_SIGN_IN_KEY: pem, APPLE_SIGN_IN_KEY_ID: "" }),
    ).toBeUndefined();
    expect(
      signInWithAppleKeyOf({ APPLE_SIGN_IN_KEY: pem, APPLE_SIGN_IN_KEY_ID: "K" }),
    ).toBeDefined();
  });
});
