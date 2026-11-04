import { Duration, Effect, Exit, Layer, Option, Redacted, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { DeviceId as DeviceIdSchema, UserId as UserIdSchema } from "@billet/contracts-domain/ids";
import { PushToken } from "@billet/contracts-domain/push-token";
import { AuthNonce, SessionToken } from "@billet/contracts-http-api/auth";
import { AppleIdInUse, AuthRejected, AuthUnavailable } from "../src/auth-error.ts";
import { AccountNotices } from "../src/account-notices.ts";
import { AuthEngine } from "../src/auth-engine.ts";
import { AuthRepository, type TokenHash } from "../src/auth-repository.ts";
import { AuthService, challengeLifetime, sessionLifetime } from "../src/auth-service.ts";
import { IdentityVerifier } from "../src/identity-verifier.ts";
import { makeInMemoryAuthEngine } from "./in-memory-auth-engine.ts";
import { makeInMemoryAuthRepository } from "./in-memory-auth-repository.ts";
import { plainExit } from "@billet/backend-observability/test/plain-exit";

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

const setup = (
  overrides: Partial<AuthRepository["Service"]> = {},
  engineOverrides: Partial<AuthEngine["Service"]> = {},
  notices: Layer.Layer<AccountNotices> = AccountNotices.none,
) => {
  const memory = makeInMemoryAuthRepository();
  const users = makeInMemoryAuthEngine();
  const repository = Layer.succeed(AuthRepository, { ...memory.repository, ...overrides });
  const engine = Layer.succeed(AuthEngine, { ...users.engine, ...engineOverrides });
  const auth = AuthService.layer.pipe(
    Layer.provide(Layer.mergeAll(repository, engine, notices, FakeIdentityVerifier)),
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
    ).then(plainExit);
  return { memory, users, run };
};

const signIn = (subject = "subject-a") =>
  Effect.gen(function* () {
    const auth = yield* service;
    const { nonce } = yield* auth.issueChallenge;
    return yield* auth.signInWithApple(identityToken(subject, nonce));
  });

/** 32 random bytes as base64url, like the app's account key. */
const accountKey = (fill: string) => Redacted.make(fill.repeat(43).slice(0, 43));

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
    const { users, run } = setup();
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
    expect(plainExit(exit)).toEqual(rejected("fake-rejected"));
    expect(retried.sessionToken).toBeDefined();
    expect(await Effect.runPromise(users.userCount)).toBe(1);
  });

  it("creates no session while the verifier is unavailable", async () => {
    const { users, run } = setup();
    const exit = await run(
      Effect.flatMap(service, (auth) => auth.signInWithApple(Redacted.make("unavailable"))),
    );
    expect(exit).toEqual(Exit.fail(new AuthUnavailable({ reason: "fake-unavailable" })));
    expect(await Effect.runPromise(users.dump)).toContain('"sessions":[]');
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

describe("AuthService anonymous accounts", () => {
  const anonymously = (key: Redacted.Redacted<string>) =>
    Effect.flatMap(service, (auth) => auth.signInAnonymously(key));

  it("opens an account the first time a key is seen, and returns to it after", async () => {
    const { users, run } = setup();
    const [first, again, other] = await value(
      run(
        Effect.all([
          anonymously(accountKey("a")),
          anonymously(accountKey("a")),
          anonymously(accountKey("b")),
        ]),
      ),
    );
    expect(again?.userId).toBe(first?.userId);
    expect(again?.deviceId).not.toBe(first?.deviceId);
    expect(again?.sessionToken).not.toBe(first?.sessionToken);
    expect(other?.userId).not.toBe(first?.userId);
    expect(await Effect.runPromise(users.userCount)).toBe(2);
  });

  it("keeps only the hash of the key", async () => {
    const { memory, run } = setup();
    const { stored, expected } = await value(
      run(
        Effect.gen(function* () {
          yield* anonymously(accountKey("a"));
          return { stored: yield* memory.dump, expected: yield* sha256("a".repeat(43)) };
        }),
      ),
    );
    expect(stored).toContain(expected);
    expect(stored).not.toContain("a".repeat(43));
  });

  it("refuses a malformed key without opening an account", async () => {
    const { users, run } = setup();
    const exit = await run(anonymously(Redacted.make("too-short")));
    expect(exit).toEqual(rejected("account-key-malformed"));
    expect(await Effect.runPromise(users.userCount)).toBe(0);
  });

  it("joins the account that won a race for the same new key", async () => {
    const memory = makeInMemoryAuthRepository().repository;
    let racing = true;
    const { users, run } = setup(
      {
        // The other first sign-in saves the key between our lookup and our save.
        findAccountKey: (keyHash) => (racing ? Effect.succeedNone : memory.findAccountKey(keyHash)),
        saveAccountKey: (keyHash, userId, at) =>
          Effect.gen(function* () {
            if (racing) {
              racing = false;
              yield* memory.saveAccountKey(keyHash, Schema.decodeSync(UserIdSchema)("winner"), at);
            }
            return yield* memory.saveAccountKey(keyHash, userId, at);
          }),
      },
      {
        startSession: (userId) =>
          Effect.succeed({
            sessionToken: Schema.decodeSync(SessionToken)("w".repeat(32)),
            userId,
            deviceId: Schema.decodeSync(DeviceIdSchema)("device-winner"),
            expiresAt: 1,
          }),
      },
    );
    const session = await value(run(anonymously(accountKey("a"))));
    expect(session.userId).toBe("winner");
    // The losing session is ended; only the user it opened is left behind, unreachable.
    expect(await Effect.runPromise(users.dump)).toContain('"sessions":[]');
  });
});

describe("AuthService account", () => {
  it("tells a user their partner left, from the notices", async () => {
    const partnerLeft = { reason: "account-deleted" as const, at: 1_700_000_400_000 };
    const { run } = setup(
      {},
      {},
      Layer.succeed(AccountNotices, {
        partnerLeft: () => Effect.succeed(Option.some(partnerLeft)),
      }),
    );
    const result = await value(
      run(
        Effect.gen(function* () {
          const auth = yield* service;
          const session = yield* auth.signInAnonymously(accountKey("a"));
          return { session, account: yield* auth.account(Redacted.make(session.sessionToken)) };
        }),
      ),
    );
    expect(result.account).toEqual({ userId: result.session.userId, linked: false, partnerLeft });
  });
});

describe("AuthService linking", () => {
  const link = (sessionToken: string, subject: string) =>
    Effect.gen(function* () {
      const auth = yield* service;
      const { nonce } = yield* auth.issueChallenge;
      return yield* auth.linkApple(Redacted.make(sessionToken), identityToken(subject, nonce));
    });

  it("links an anonymous account to Apple and keeps the same user", async () => {
    const { run } = setup();
    const result = await value(
      run(
        Effect.gen(function* () {
          const auth = yield* service;
          const anonymous = yield* auth.signInAnonymously(accountKey("a"));
          const before = yield* auth.account(Redacted.make(anonymous.sessionToken));
          const linked = yield* link(anonymous.sessionToken, "subject-a");
          const after = yield* auth.account(Redacted.make(anonymous.sessionToken));
          // A new phone without the keychain signs in with Apple and lands in the same account.
          const restored = yield* signIn("subject-a");
          return { anonymous, before, linked, after, restored };
        }),
      ),
    );
    expect(result.before).toEqual({ userId: result.anonymous.userId, linked: false });
    expect(result.linked).toEqual({ userId: result.anonymous.userId, linked: true });
    expect(result.after).toEqual({ userId: result.anonymous.userId, linked: true });
    expect(result.restored.userId).toBe(result.anonymous.userId);
  });

  it("refuses an Apple ID that belongs to another account", async () => {
    const { run } = setup();
    const exit = await run(
      Effect.gen(function* () {
        yield* signIn("subject-a");
        const auth = yield* service;
        const anonymous = yield* auth.signInAnonymously(accountKey("a"));
        return yield* link(anonymous.sessionToken, "subject-a");
      }),
    );
    expect(exit).toEqual(Exit.fail(new AppleIdInUse()));
  });

  it("refuses a caller without a live session before verifying anything", async () => {
    const { run } = setup();
    const exit = await run(link("x".repeat(43), "subject-a"));
    expect(exit).toEqual(rejected("session-not-live"));
  });

  it("refuses a replayed identity token", async () => {
    const { run } = setup();
    const exit = await run(
      Effect.gen(function* () {
        const auth = yield* service;
        const { sessionToken } = yield* auth.signInAnonymously(accountKey("a"));
        const { nonce } = yield* auth.issueChallenge;
        yield* auth.linkApple(Redacted.make(sessionToken), identityToken("subject-a", nonce));
        return yield* auth.linkApple(
          Redacted.make(sessionToken),
          identityToken("subject-a", nonce),
        );
      }),
    );
    expect(exit).toEqual(rejected("nonce-not-live"));
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
    const { run } = setup({}, { findSession: () => Effect.die("storage must not be read") });
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
});
