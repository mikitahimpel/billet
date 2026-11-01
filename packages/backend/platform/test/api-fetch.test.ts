import { env, exports } from "cloudflare:workers";
import { Effect, Layer, Redacted, Schema } from "effect";
import { SecureRandom, Signature } from "effect/crypto";
import { Base64Url } from "effect/encoding";
import { Jwk, Jws } from "effect/jose";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  appleAudience,
  appleIssuer,
  appleKeysUrl,
} from "@billet/backend-auth/apple-identity-verifier";
import { AuthChallengeResponse, SessionResponse } from "@billet/contracts-http-api/auth";
import { resetDirectory } from "./directory-migrations.ts";

const cryptoLayer = Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto));

const appleKeys = await Effect.runPromise(
  Effect.gen(function* () {
    const pair = yield* Jwk.generateKeyPair({ algorithm: "RS256", kid: "apple-1" });
    return {
      privateKey: yield* Jwk.importPrivate(pair.privateKey, "RS256"),
      publicJwk: pair.publicKey,
    };
  }).pipe(Effect.provide(cryptoLayer)),
);

const claims = (nonce: string, overrides: Record<string, unknown> = {}) =>
  new TextEncoder().encode(
    JSON.stringify({
      iss: appleIssuer,
      aud: appleAudience,
      sub: "subject-a",
      nonce,
      exp: Math.floor(Date.now() / 1000) + 300,
      ...overrides,
    }),
  );

const identityToken = (nonce: string, overrides?: Record<string, unknown>) =>
  Effect.runPromise(
    Jws.sign(claims(nonce, overrides), appleKeys.privateKey).pipe(
      Effect.map(Redacted.value),
      Effect.provide(cryptoLayer),
    ),
  );

const call = (path: string, init: RequestInit = {}) =>
  exports.default.fetch(new Request(`https://billet.test${path}`, { method: "POST", ...init }));

const json = (body: unknown, method = "POST", token?: string): RequestInit => ({
  method,
  body: JSON.stringify(body),
  headers: {
    "content-type": "application/json",
    ...(token === undefined ? {} : { authorization: `Bearer ${token}` }),
  },
});

const challenge = async () =>
  Schema.decodeUnknownSync(AuthChallengeResponse)(await (await call("/v1/auth/challenge")).json());

const signIn = async (overrides?: Record<string, unknown>) => {
  const { nonce } = await challenge();
  return {
    nonce,
    response: await call(
      "/v1/auth/apple",
      json({ identityToken: await identityToken(nonce, overrides) }),
    ),
  };
};

const signedIn = async () => {
  const { nonce, response } = await signIn();
  expect(response.status).toBe(200);
  return { nonce, session: Schema.decodeUnknownSync(SessionResponse)(await response.json()) };
};

const tables = ["users", "devices", "sessions", "auth_challenges", "push_tokens"];

const everythingStored = async () =>
  JSON.stringify(
    await Promise.all(
      tables.map(async (table) => (await env.DB.prepare(`SELECT * FROM ${table}`).all()).results),
    ),
  );

const sha256Hex = async (text: string) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

const appleFetch = vi.fn<typeof fetch>();

beforeAll(() => {
  vi.stubGlobal("fetch", appleFetch);
});

beforeEach(async () => {
  await resetDirectory();
  appleFetch.mockReset();
  appleFetch.mockImplementation(async (input) => {
    expect(String(input)).toBe(appleKeysUrl);
    await new Promise((resolve) => setTimeout(resolve, 20));
    return Response.json({ keys: [appleKeys.publicJwk] });
  });
});

describe("the Api Worker", () => {
  it("still answers the deploy smoke test outside /v1/", async () => {
    const response = await exports.default.fetch("https://billet.test/");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ service: "billet-api", status: "ok" });
  });

  it("answers 404 for an unknown /v1/ route", async () => {
    expect((await call("/v1/nothing")).status).toBe(404);
  });

  it("keeps only hashes of the session token and the nonce in D1", async () => {
    expect(await everythingStored()).not.toContain((await challenge()).nonce);

    const { nonce, session } = await signedIn();
    const stored = await everythingStored();
    expect(stored).not.toContain(session.sessionToken);
    expect(stored).not.toContain(nonce);

    const rows = await env.DB.prepare("SELECT token_hash FROM sessions").all();
    expect(rows.results).toEqual([{ token_hash: await sha256Hex(session.sessionToken) }]);
  });

  it("registers a device's push token and replaces it", async () => {
    const { session } = await signedIn();
    const register = (token: string) =>
      call(
        "/v1/devices/current/push-token",
        json({ kind: "alert", environment: "production", token }, "PUT", session.sessionToken),
      );

    expect((await register("aa".repeat(32))).status).toBe(204);
    expect((await register("bb".repeat(32))).status).toBe(204);

    const rows = await env.DB.prepare("SELECT device_id, kind, token FROM push_tokens").all();
    expect(rows.results).toEqual([
      { device_id: session.deviceId, kind: "alert", token: "bb".repeat(32) },
    ]);
  });

  it("revokes the session on sign-out", async () => {
    const { session } = await signedIn();
    const signOut = () =>
      call("/v1/auth/sign-out", {
        headers: { authorization: `Bearer ${session.sessionToken}` },
      });
    expect((await signOut()).status).toBe(204);
    expect((await signOut()).status).toBe(401);
  });

  it.each([
    ["expired", { exp: Math.floor(Date.now() / 1000) - 300 }],
    ["wrong-audience", { aud: "com.example.other" }],
  ])("refuses an %s token and stores no session", async (_, overrides) => {
    const { response } = await signIn(overrides);
    expect(response.status).toBe(401);
    expect(await env.DB.prepare("SELECT * FROM sessions").first()).toBeNull();
  });

  it("refuses a tampered token and leaves its nonce live", async () => {
    const { nonce } = await challenge();
    const [header, , signature] = (await identityToken(nonce)).split(".");
    const forgedPayload = Base64Url.encode(claims(nonce, { sub: "someone-else" }));
    const tampered = [header, forgedPayload, signature].join(".");

    expect((await call("/v1/auth/apple", json({ identityToken: tampered }))).status).toBe(401);
    expect(await env.DB.prepare("SELECT * FROM users").first()).toBeNull();
    expect(
      (await call("/v1/auth/apple", json({ identityToken: await identityToken(nonce) }))).status,
    ).toBe(200);
  });

  it("refuses a replayed identity token", async () => {
    const { nonce } = await challenge();
    const token = await identityToken(nonce);
    expect((await call("/v1/auth/apple", json({ identityToken: token }))).status).toBe(200);
    expect((await call("/v1/auth/apple", json({ identityToken: token }))).status).toBe(401);
  });

  it("answers 503 and grants nothing when Apple's keys can't be read", async () => {
    appleFetch.mockRejectedValue(new Error("offline"));
    const { response } = await signIn();
    expect(response.status).toBe(503);
    expect(await env.DB.prepare("SELECT * FROM sessions").first()).toBeNull();
  });

  it("serves concurrent sign-ins while no keys are loaded, each on its own fetch", async () => {
    const results = await Promise.all(Array.from({ length: 5 }, () => signIn()));
    expect(results.map(({ response }) => response.status)).toEqual([200, 200, 200, 200, 200]);
    expect(appleFetch).toHaveBeenCalledTimes(5);
  });
});
