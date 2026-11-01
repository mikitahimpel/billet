import { Duration, Effect, Exit, Layer, Redacted, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { PushToken } from "@billet/contracts-domain/push-token";
import { AuthNonce, SessionToken } from "@billet/contracts-http-api/auth";
import { AuthRejected, AuthUnavailable } from "../src/auth-error.ts";
import { AuthRepository, type TokenHash } from "../src/auth-repository.ts";
import { AuthService, challengeLifetime, sessionLifetime } from "../src/auth-service.ts";
import { IdentityVerifier } from "../src/identity-verifier.ts";
import { makeInMemoryAuthRepository } from "./in-memory-auth-repository.ts";

const startMillis = 1_800_000_000_000;

/** The fake verifier: the "token" is the identity JSON, or a name for how to fail. */
const FakeIdentityVerifier = Layer.succeed(IdentityVerifier, {
  verify: (token) => {
    const raw = Redacted.value(token);
    if (raw === "rejected") return Effect.fail(new AuthRejected({ reason: "fake-rejected" }));
    if (raw === "unavailable") {
      return Effect.fail(new AuthUnavailable({ reason: "fake-unavailable" }));
    }
    return Effect.succeed(JSON.parse(raw) as { subject: string; nonce: string });
  },
});

const identityToken = (subject: string, nonce: string) =>
  Redacted.make(JSON.stringify({ subject, nonce }));

const sha256 = (value: string): Effect.Effect<TokenHash, never, Digest.Digest> =>
  Effect.gen(function* () {
    const digest = yield* Digest.Digest;
    return yield* digest.digestHex(Digest.sha256, new TextEncoder().encode(value));
  });

const service = Effect.gen(function* () {
  return yield* AuthService;
});

const setup = (overrides: Partial<AuthRepository["Service"]> = {}) => {
  const memory = makeInMemoryAuthRepository();
  const repository = Layer.succeed(AuthRepository, { ...memory.repository, ...overrides });
  const auth = AuthService.layer.pipe(
    Layer.provide(Layer.mergeAll(repository, FakeIdentityVerifier)),
    Layer.provideMerge(Layer.merge(Digest.layerWebCrypto, SecureRandom.layerWebCrypto)),
  );
  const run = <A, E>(
    program: Effect.Effect<
      A,
      E,
      AuthService | Digest.Digest | SecureRandom.SecureRandom | TestClock.TestClock
    >,
  ) =>
    Effect.runPromiseExit(
      TestClock.setTime(startMillis).pipe(
        Effect.andThen(program),
        Effect.provide(Layer.merge(auth, TestClock.layer())),
      ),
    );
  return { memory, run };
};

const signIn = (subject = "subject-a") =>
  Effect.gen(function* () {
    const auth = yield* service;
    const { nonce } = yield* auth.issueChallenge;
    return yield* auth.signInWithApple(identityToken(subject, nonce));
  });

const rejected = (reason: string) => Exit.fail(new AuthRejected({ reason }));

const value = async <A, E>(exit: Promise<Exit.Exit<A, E>>): Promise<A> => {
  const result = await exit;
  if (Exit.isFailure(result)) throw new Error(`expected success: ${String(result.cause)}`);
  return result.value;
};

describe("AuthService challenges", () => {
  it("issues a high-entropy nonce and stores only its hash", async () => {
    const { memory, run } = setup();
    const { nonce, stored, expected, first, second } = await value(
      run(
        Effect.gen(function* () {
          const auth = yield* service;
          const first = yield* auth.issueChallenge;
          const second = yield* auth.issueChallenge;
          return {
            nonce: first.nonce,
            first,
            second,
            stored: yield* memory.dump,
            expected: yield* sha256(first.nonce),
          };
        }),
      ),
    );
    expect(Schema.is(AuthNonce)(nonce)).toBe(true);
    expect(first.nonce).not.toBe(second.nonce);
    expect(first.expiresAt).toBe(startMillis + Duration.toMillis(challengeLifetime));
    expect(stored).toContain(expected);
    expect(stored).not.toContain(nonce);
  });
});

describe("AuthService sign-in", () => {
  it("creates a session for a verified identity with a live nonce", async () => {
    const { run } = setup();
    const session = await value(run(signIn()));
    expect(Schema.is(SessionToken)(session.sessionToken)).toBe(true);
    expect(session.expiresAt).toBe(startMillis + Duration.toMillis(sessionLifetime));
  });

  it("keeps only the hash of the session token in storage", async () => {
    const { memory, run } = setup();
    const { session, stored, expected } = await value(
      run(
        Effect.gen(function* () {
          const session = yield* signIn();
          return {
            session,
            stored: yield* memory.dump,
            expected: yield* sha256(session.sessionToken),
          };
        }),
      ),
    );
    expect(stored).toContain(expected);
    expect(stored).not.toContain(session.sessionToken);
  });

  it("gives the same user a new session and device on each sign-in", async () => {
    const { run } = setup();
    const [first, second] = await value(run(Effect.all([signIn(), signIn()])));
    expect(second?.userId).toBe(first?.userId);
    expect(second?.deviceId).not.toBe(first?.deviceId);
    expect(second?.sessionToken).not.toBe(first?.sessionToken);
  });

  it("gives different Apple subjects different users", async () => {
    const { run } = setup();
    const [first, second] = await value(run(Effect.all([signIn("a"), signIn("b")])));
    expect(second?.userId).not.toBe(first?.userId);
  });

  it("refuses a replayed identity token", async () => {
    const { run } = setup();
    const exit = await run(
      Effect.gen(function* () {
        const auth = yield* service;
        const { nonce } = yield* auth.issueChallenge;
        yield* auth.signInWithApple(identityToken("subject-a", nonce));
        return yield* auth.signInWithApple(identityToken("subject-a", nonce));
      }),
    );
    expect(exit).toEqual(rejected("nonce-not-live"));
  });

  it("refuses a nonce the server never issued", async () => {
    const { run } = setup();
    const exit = await run(
      Effect.flatMap(service, (auth) =>
        auth.signInWithApple(identityToken("subject-a", "made-up")),
      ),
    );
    expect(exit).toEqual(rejected("nonce-not-live"));
  });

  it("refuses an expired nonce", async () => {
    const { run } = setup();
    const exit = await run(
      Effect.gen(function* () {
        const auth = yield* service;
        const { nonce } = yield* auth.issueChallenge;
        yield* TestClock.adjust(challengeLifetime);
        return yield* auth.signInWithApple(identityToken("subject-a", nonce));
      }),
    );
    expect(exit).toEqual(rejected("nonce-not-live"));
  });

  it("creates nothing and leaves the nonce unused when verification fails", async () => {
    const { memory, run } = setup();
    const { exit, retried } = await value(
      run(
        Effect.gen(function* () {
          const auth = yield* service;
          const { nonce } = yield* auth.issueChallenge;
          const exit = yield* Effect.exit(auth.signInWithApple(Redacted.make("rejected")));
          const retried = yield* auth.signInWithApple(identityToken("subject-a", nonce));
          return { exit, retried };
        }),
      ),
    );
    expect(exit).toEqual(rejected("fake-rejected"));
    expect(retried.sessionToken).toBeDefined();
    expect(await Effect.runPromise(memory.dump)).toContain('"users":[[');
  });

  it("creates no session while the verifier is unavailable", async () => {
    const { memory, run } = setup();
    const exit = await run(
      Effect.flatMap(service, (auth) => auth.signInWithApple(Redacted.make("unavailable"))),
    );
    expect(exit).toEqual(Exit.fail(new AuthUnavailable({ reason: "fake-unavailable" })));
    expect(await Effect.runPromise(memory.dump)).toContain('"sessions":[]');
  });

  it("fails closed when storage fails", async () => {
    const down = Effect.fail(new AuthUnavailable({ reason: "storage" }));
    const { run } = setup({ consumeChallenge: () => down });
    expect(await run(signIn())).toEqual(Exit.fail(new AuthUnavailable({ reason: "storage" })));
  });

  it("still signs in when housekeeping fails", async () => {
    const { run } = setup({
      deleteExpired: () => Effect.fail(new AuthUnavailable({ reason: "storage" })),
    });
    expect(Exit.isSuccess(await run(signIn()))).toBe(true);
  });
});

describe("AuthService authenticate", () => {
  it("accepts a live session token", async () => {
    const { run } = setup();
    const { session, principal } = await value(
      run(
        Effect.gen(function* () {
          const session = yield* signIn();
          const auth = yield* service;
          const principal = yield* auth.authenticate(Redacted.make(session.sessionToken));
          return { session, principal };
        }),
      ),
    );
    expect(principal.userId).toBe(session.userId);
    expect(principal.deviceId).toBe(session.deviceId);
  });

  it("refuses a malformed token without reading storage", async () => {
    const { run } = setup({ findSession: () => Effect.die("storage must not be read") });
    const exit = await run(
      Effect.flatMap(service, (auth) => auth.authenticate(Redacted.make("short"))),
    );
    expect(exit).toEqual(rejected("session-malformed"));
  });

  it("refuses a well-formed token it never issued", async () => {
    const { run } = setup();
    const exit = await run(
      Effect.flatMap(service, (auth) => auth.authenticate(Redacted.make("x".repeat(43)))),
    );
    expect(exit).toEqual(rejected("session-not-live"));
  });

  it("refuses the stored hash used as a token", async () => {
    const { run } = setup();
    const exit = await run(
      Effect.gen(function* () {
        const { sessionToken } = yield* signIn();
        const auth = yield* service;
        return yield* auth.authenticate(Redacted.make(yield* sha256(sessionToken)));
      }),
    );
    expect(exit).toEqual(rejected("session-malformed"));
  });

  it("refuses an expired session", async () => {
    const { run } = setup();
    const exit = await run(
      Effect.gen(function* () {
        const { sessionToken } = yield* signIn();
        yield* TestClock.adjust(sessionLifetime);
        const auth = yield* service;
        return yield* auth.authenticate(Redacted.make(sessionToken));
      }),
    );
    expect(exit).toEqual(rejected("session-not-live"));
  });

  it("slides the expiry of a session in use", async () => {
    const { run } = setup();
    const exit = await run(
      Effect.gen(function* () {
        const { sessionToken } = yield* signIn();
        const auth = yield* service;
        yield* TestClock.adjust(Duration.days(60));
        yield* auth.authenticate(Redacted.make(sessionToken));
        yield* TestClock.adjust(Duration.days(60));
        return yield* auth.authenticate(Redacted.make(sessionToken));
      }),
    );
    expect(Exit.isSuccess(exit)).toBe(true);
  });

  it("writes the renewal at most once a day", async () => {
    let writes = 0;
    const memory = makeInMemoryAuthRepository().repository;
    const { run } = setup({
      createSession: memory.createSession,
      findSession: memory.findSession,
      extendSession: (hash, expiresAt) => {
        writes += 1;
        return memory.extendSession(hash, expiresAt);
      },
    });
    await value(
      run(
        Effect.gen(function* () {
          const { sessionToken } = yield* signIn();
          const auth = yield* service;
          const use = auth.authenticate(Redacted.make(sessionToken));
          yield* use;
          yield* TestClock.adjust(Duration.hours(23));
          yield* use;
          yield* TestClock.adjust(Duration.hours(2));
          yield* use;
          yield* use;
        }),
      ),
    );
    expect(writes).toBe(1);
  });

  it("refuses a token after sign-out", async () => {
    const { run } = setup();
    const exit = await run(
      Effect.gen(function* () {
        const { sessionToken } = yield* signIn();
        const auth = yield* service;
        yield* auth.signOut(yield* auth.authenticate(Redacted.make(sessionToken)));
        return yield* auth.authenticate(Redacted.make(sessionToken));
      }),
    );
    expect(exit).toEqual(rejected("session-not-live"));
  });
});

describe("AuthService push tokens", () => {
  const token = Schema.decodeSync(PushToken);

  it("registers a device's token and replaces it", async () => {
    const { memory, run } = setup();
    const stored = await value(
      run(
        Effect.gen(function* () {
          const { sessionToken, deviceId } = yield* signIn();
          const auth = yield* service;
          const principal = yield* auth.authenticate(Redacted.make(sessionToken));
          const request = { kind: "alert", environment: "production" } as const;
          yield* auth.registerPushToken(principal, { ...request, token: token("aa".repeat(32)) });
          yield* auth.registerPushToken(principal, { ...request, token: token("bb".repeat(32)) });
          return yield* memory.repository.listPushTokens(deviceId);
        }),
      ),
    );
    expect(stored).toEqual([
      {
        kind: "alert",
        environment: "production",
        token: "bb".repeat(32),
        updatedAt: startMillis,
      },
    ]);
  });

  it("stops a signed-out device from receiving pushes", async () => {
    const { memory, run } = setup();
    const stored = await value(
      run(
        Effect.gen(function* () {
          const { sessionToken, deviceId } = yield* signIn();
          const auth = yield* service;
          const principal = yield* auth.authenticate(Redacted.make(sessionToken));
          yield* auth.registerPushToken(principal, {
            kind: "widget",
            environment: "sandbox",
            token: token("aa".repeat(32)),
          });
          yield* auth.signOut(principal);
          return yield* memory.repository.listPushTokens(deviceId);
        }),
      ),
    );
    expect(stored).toEqual([]);
  });
});
