import { Duration, Effect, Exit, Fiber, Layer, Redacted } from "effect";
import { SecureRandom, Signature } from "effect/crypto";
import { Base64Url } from "effect/encoding";
import { HttpClient, HttpClientError, HttpClientResponse } from "effect/http";
import { Jwk, Jwks, Jws } from "effect/jose";
import { TestClock } from "effect/testing";
import { beforeAll, describe, expect, it } from "vitest";
import {
  appleAudience,
  appleIssuer,
  appleKeysUrl,
  AppleIdentityVerifier,
} from "../src/apple-identity-verifier.ts";
import { AuthRejected, AuthUnavailable } from "../src/auth-error.ts";
import { IdentityVerifier } from "../src/identity-verifier.ts";

const nowMillis = 1_800_000_000_000;
const nowSeconds = nowMillis / 1000;

const cryptoLayer = Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto));

interface TestKey {
  readonly publicJwk: Jwk.PublicJwk;
  readonly privateKey: Jwk.PrivateKey;
}

const generateKey = (algorithm: Jwk.AsymmetricAlgorithm, kid: string): Promise<TestKey> =>
  Effect.runPromise(
    Effect.gen(function* () {
      const pair = yield* Jwk.generateKeyPair({ algorithm, kid });
      return {
        publicJwk: pair.publicKey,
        privateKey: yield* Jwk.importPrivate(pair.privateKey, algorithm),
      };
    }).pipe(Effect.provide(cryptoLayer)),
  );

let apple: TestKey;
let rotated: TestKey;
let attacker: TestKey;
let wrongAlgorithm: TestKey;

beforeAll(async () => {
  apple = await generateKey("RS256", "apple-1");
  rotated = await generateKey("RS256", "apple-2");
  // Claims Apple's key id: only the signature can tell it apart.
  attacker = await generateKey("RS256", "apple-1");
  wrongAlgorithm = await generateKey("RS384", "apple-rs384");
});

const validClaims = () => ({
  iss: appleIssuer,
  aud: appleAudience,
  sub: "001234.apple-subject",
  nonce: "nonce-1",
  iat: nowSeconds - 10,
  exp: nowSeconds + 300,
});

const encodeJson = (value: unknown): Uint8Array => new TextEncoder().encode(JSON.stringify(value));

const sign = (
  claims: unknown,
  key: TestKey = apple,
  header?: Jws.Header,
): Promise<Redacted.Redacted<string>> =>
  Effect.runPromise(
    Jws.sign(encodeJson(claims), key.privateKey, header).pipe(Effect.provide(cryptoLayer)),
  );

const segment = (value: unknown): string => Base64Url.encode(encodeJson(value));

/** The Apple endpoint as a scripted fake: nothing in these tests reaches the network. */
const fakeApple = (respond: (attempt: number) => Response | "network-error" | "hang") => {
  const calls = { count: 0, urls: [] as Array<string> };
  const client = HttpClient.make((request, url) => {
    calls.count += 1;
    calls.urls.push(url.href);
    const outcome = respond(calls.count);
    if (outcome === "hang") return Effect.never;
    if (outcome === "network-error") {
      return Effect.fail(
        new HttpClientError.HttpClientError({
          reason: new HttpClientError.TransportError({ request, description: "offline" }),
        }),
      );
    }
    return Effect.succeed(HttpClientResponse.fromWeb(request, outcome));
  });
  return { calls, client };
};

const keySet = (...keys: ReadonlyArray<TestKey>): Response =>
  Response.json({ keys: keys.map((key) => key.publicJwk) });

const run = <A, E>(
  client: HttpClient.HttpClient,
  program: Effect.Effect<A, E, IdentityVerifier | TestClock.TestClock>,
): Promise<Exit.Exit<A, E>> => {
  const jwks = Jwks.layerRemote({ url: appleKeysUrl }).pipe(
    Layer.orDie,
    Layer.provide(Layer.succeed(HttpClient.HttpClient, client)),
  );
  const verifier = AppleIdentityVerifier.pipe(Layer.provide(jwks), Layer.provide(cryptoLayer));
  return Effect.runPromiseExit(
    TestClock.setTime(nowMillis).pipe(
      Effect.andThen(program),
      Effect.provide(Layer.merge(verifier, TestClock.layer())),
    ),
  );
};

const verify = Effect.fnUntraced(function* (token: Redacted.Redacted<string>) {
  const verifier = yield* IdentityVerifier;
  return yield* verifier.verify(token);
});

const failure = (reason: string) => new AuthRejected({ reason });

const expectRejected = async (token: Redacted.Redacted<string>, reason: string) => {
  const { client } = fakeApple(() => keySet(apple, wrongAlgorithm));
  expect(await run(client, verify(token))).toEqual(Exit.fail(failure(reason)));
};

const expectUnavailable = (exit: Exit.Exit<unknown, unknown>) =>
  expect(exit).toEqual(Exit.fail(new AuthUnavailable({ reason: "apple-keys-unavailable" })));

describe("AppleIdentityVerifier", () => {
  it("accepts a token signed by Apple's key, and asks only Apple's key endpoint", async () => {
    const { calls, client } = fakeApple(() => keySet(apple));
    const exit = await run(client, verify(await sign(validClaims())));
    expect(exit).toEqual(Exit.succeed({ subject: "001234.apple-subject", nonce: "nonce-1" }));
    expect(calls.urls).toEqual([appleKeysUrl]);
  });

  describe("rejects", () => {
    it("an expired token", async () => {
      const claims = { ...validClaims(), exp: nowSeconds - 1 };
      await expectRejected(await sign(claims), "claim-exp-expired");
    });

    it("a token expiring this very second", async () => {
      const claims = { ...validClaims(), exp: nowSeconds };
      await expectRejected(await sign(claims), "claim-exp-expired");
    });

    it("a token without an expiry", async () => {
      const { exp: _exp, ...claims } = validClaims();
      await expectRejected(await sign(claims), "claim-exp-missing");
    });

    it("a token for another audience", async () => {
      const claims = { ...validClaims(), aud: "com.example.other" };
      await expectRejected(await sign(claims), "claim-aud-mismatch");
    });

    it("an audience list that merely contains the bundle id", async () => {
      const claims = { ...validClaims(), aud: ["com.example.other", appleAudience] };
      await expectRejected(await sign(claims), "claims-invalid");
    });

    it("a token from another issuer", async () => {
      const claims = { ...validClaims(), iss: "https://appleid.apple.com.evil.example" };
      await expectRejected(await sign(claims), "claim-iss-mismatch");
    });

    it("a tampered payload", async () => {
      const token = Redacted.value(await sign(validClaims()));
      const [header, , signature] = token.split(".");
      const forged = segment({ ...validClaims(), sub: "someone-else" });
      await expectRejected(
        Redacted.make(`${header}.${forged}.${signature}`),
        "SignatureVerificationFailed",
      );
    });

    it("a tampered signature", async () => {
      const token = Redacted.value(await sign(validClaims()));
      const [header, payload, signature = ""] = token.split(".");
      const flipped = `${signature[0] === "A" ? "B" : "A"}${signature.slice(1)}`;
      await expectRejected(
        Redacted.make(`${header}.${payload}.${flipped}`),
        "SignatureVerificationFailed",
      );
    });

    it("a token signed by another key under Apple's key id", async () => {
      await expectRejected(await sign(validClaims(), attacker), "SignatureVerificationFailed");
    });

    it("an unsigned alg:none token", async () => {
      const header = segment({ alg: "none", kid: "apple-1" });
      await expectRejected(Redacted.make(`${header}.${segment(validClaims())}.`), "InvalidToken");
    });

    it("HS256 signed with the public key as the secret", async () => {
      const header = segment({ alg: "HS256", kid: "apple-1" });
      const payload = segment(validClaims());
      const secret = await crypto.subtle.importKey(
        "raw",
        encodeJson(apple.publicJwk),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
      );
      const mac = await crypto.subtle.sign(
        "HMAC",
        secret,
        new TextEncoder().encode(`${header}.${payload}`),
      );
      await expectRejected(
        Redacted.make(`${header}.${payload}.${Base64Url.encode(new Uint8Array(mac))}`),
        "AlgorithmNotAllowed",
      );
    });

    it("a valid signature from a published key under another algorithm", async () => {
      await expectRejected(await sign(validClaims(), wrongAlgorithm), "AlgorithmNotAllowed");
    });

    it("a token with no key id, when the key set has several RS256 keys", async () => {
      const { client } = fakeApple(() => keySet(apple, rotated));
      const unkeyed = { ...apple, privateKey: { ...apple.privateKey, kid: undefined } };
      const exit = await run(client, verify(await sign(validClaims(), unkeyed)));
      expect(exit).toEqual(Exit.fail(failure("AmbiguousKey")));
    });

    it("a token without a subject", async () => {
      const { sub: _sub, ...claims } = validClaims();
      await expectRejected(await sign(claims), "claim-sub-missing");
    });

    it("a token without a nonce", async () => {
      const { nonce: _nonce, ...claims } = validClaims();
      await expectRejected(await sign(claims), "claims-invalid");
    });

    it("an empty nonce", async () => {
      await expectRejected(await sign({ ...validClaims(), nonce: "" }), "claims-invalid");
    });

    it("something that is not a JWT", async () => {
      await expectRejected(Redacted.make("not-a-token"), "InvalidToken");
    });
  });

  describe("key rotation", () => {
    it("reuses cached keys for a known key id", async () => {
      const { calls, client } = fakeApple(() => keySet(apple));
      const token = await sign(validClaims());
      await run(client, Effect.andThen(verify(token), verify(token)));
      expect(calls.count).toBe(1);
    });

    it("refetches for an unknown key id and accepts the rotated key", async () => {
      const { calls, client } = fakeApple((attempt) =>
        attempt === 1 ? keySet(apple) : keySet(apple, rotated),
      );
      const before = await sign(validClaims());
      const after = await sign(validClaims(), rotated);
      const exit = await run(
        client,
        Effect.gen(function* () {
          yield* verify(before);
          yield* TestClock.adjust(Duration.seconds(31));
          return yield* verify(after);
        }),
      );
      expect(Exit.isSuccess(exit)).toBe(true);
      expect(calls.count).toBe(2);
    });

    it("rejects a key id still unknown after refetching", async () => {
      const { client } = fakeApple(() => keySet(apple));
      const token = await sign(validClaims(), rotated);
      const exit = await run(client, verify(token));
      expect(exit).toEqual(Exit.fail(failure("KeyNotFound")));
    });

    it("does not let unknown key ids drive a request per token", async () => {
      const { calls, client } = fakeApple(() => keySet(apple));
      const known = await sign(validClaims());
      const unknown = await sign(validClaims(), rotated);
      const attempt = Effect.exit(verify(unknown));
      await run(
        client,
        Effect.gen(function* () {
          yield* verify(known);
          yield* TestClock.adjust(Duration.seconds(31));
          yield* attempt;
          yield* attempt;
          yield* attempt;
        }),
      );
      expect(calls.count).toBe(2);
    });

    it("drops a key Apple has retired once the cache expires", async () => {
      const { client } = fakeApple((attempt) => (attempt === 1 ? keySet(apple) : keySet(rotated)));
      const token = await sign(validClaims());
      const exit = await run(
        client,
        Effect.gen(function* () {
          yield* verify(token);
          yield* TestClock.adjust(Duration.minutes(11));
          return yield* verify(token);
        }),
      );
      expect(exit).toEqual(Exit.fail(failure("KeyNotFound")));
    });
  });

  describe("fails closed when Apple's keys can't be read", () => {
    const failing: ReadonlyArray<readonly [string, () => Response | "network-error"]> = [
      ["a network error", () => "network-error"],
      ["a server error", () => new Response("oops", { status: 500 })],
      ["a redirect", () => new Response(null, { status: 302 })],
      ["a body that isn't JSON", () => new Response("<html>")],
      ["a document that isn't a key set", () => Response.json({ keys: "none" })],
      ["a key set with private members", () => Response.json({ keys: [{ kty: "oct", k: "AA" }] })],
    ];

    it.each(failing)("on %s", async (_name, respond) => {
      const { client } = fakeApple(respond);
      expectUnavailable(await run(client, verify(await sign(validClaims()))));
    });

    it("on a request that never answers", async () => {
      const { client } = fakeApple(() => "hang");
      const token = await sign(validClaims());
      const exit = await run(
        client,
        Effect.gen(function* () {
          const pending = yield* Effect.forkChild(verify(token));
          yield* TestClock.adjust(Duration.seconds(6));
          return yield* Fiber.join(pending);
        }),
      );
      expectUnavailable(exit);
    });

    it("rather than use an expired key set", async () => {
      const { client } = fakeApple((attempt) => (attempt === 1 ? keySet(apple) : "network-error"));
      const token = await sign(validClaims());
      const exit = await run(
        client,
        Effect.gen(function* () {
          yield* verify(token);
          yield* TestClock.adjust(Duration.minutes(11));
          return yield* verify(token);
        }),
      );
      expectUnavailable(exit);
    });

    it("and recovers on a later request", async () => {
      const { client } = fakeApple((attempt) => (attempt === 1 ? "network-error" : keySet(apple)));
      const token = await sign(validClaims());
      const exit = await run(
        client,
        Effect.gen(function* () {
          yield* Effect.exit(verify(token));
          yield* TestClock.adjust(Duration.seconds(31));
          return yield* verify(token);
        }),
      );
      expect(Exit.isSuccess(exit)).toBe(true);
    });
  });
});
