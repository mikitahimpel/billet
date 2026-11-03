import { Effect, Layer, Redacted, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { afterAll, afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AuthChallengeResponse, SessionResponse } from "@billet/contracts-http-api/auth";
import { AuthRejected, AuthUnavailable } from "../src/auth-error.ts";
import { AuthEngine } from "../src/auth-engine.ts";
import { AuthRepository } from "../src/auth-repository.ts";
import { AuthRoutes } from "../src/auth-routes.ts";
import { AuthService } from "../src/auth-service.ts";
import { IdentityVerifier } from "../src/identity-verifier.ts";
import { makeInMemoryAuthEngine } from "./in-memory-auth-engine.ts";
import { makeInMemoryAuthRepository } from "./in-memory-auth-repository.ts";

let verifyCalls = 0;

const FakeIdentityVerifier = Layer.succeed(IdentityVerifier, {
  verify: (token) => {
    verifyCalls += 1;
    const raw = Redacted.value(token);
    if (raw === "apple-down") return Effect.fail(new AuthUnavailable({ reason: "fake" }));
    if (raw.startsWith("bad")) return Effect.fail(new AuthRejected({ reason: "fake" }));
    return Effect.succeed({ subject: "subject-a", nonce: raw });
  },
});

const setup = () => {
  const memory = makeInMemoryAuthRepository();
  const app = AuthRoutes.pipe(
    Layer.provide(AuthService.layer),
    Layer.provide(
      Layer.mergeAll(
        Layer.succeed(AuthRepository, memory.repository),
        Layer.succeed(AuthEngine, makeInMemoryAuthEngine().engine),
        FakeIdentityVerifier,
        Digest.layerWebCrypto,
        SecureRandom.layerWebCrypto,
      ),
    ),
  );
  return { memory, ...HttpRouter.toWebHandler(app, { disableLogger: true }) };
};

const request = (path: string, init: RequestInit = {}) =>
  new Request(`http://billet.test${path}`, { method: "POST", ...init });

const json = (body: unknown, token?: string, method = "POST"): RequestInit => ({
  method,
  body: JSON.stringify(body),
  headers: {
    "content-type": "application/json",
    ...(token === undefined ? {} : { authorization: `Bearer ${token}` }),
  },
});

const signIn = async (handler: (request: Request) => Promise<Response>) => {
  const challenge = Schema.decodeUnknownSync(AuthChallengeResponse)(
    await (await handler(request("/v1/auth/challenge"))).json(),
  );
  const response = await handler(
    request("/v1/auth/apple", json({ identityToken: challenge.nonce })),
  );
  return { response, session: Schema.decodeUnknownSync(SessionResponse)(await response.json()) };
};

const alert = { kind: "alert", environment: "production", token: "ab".repeat(32) };

describe("auth routes", () => {
  const app = setup();
  const { handler } = app;
  afterAll(() => app.dispose());

  it("runs the whole flow: challenge, sign-in, push token, sign-out", async () => {
    const { session, response } = await signIn(handler);
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");

    const register = await handler(
      request("/v1/devices/current/push-token", json(alert, session.sessionToken, "PUT")),
    );
    expect(register.status).toBe(204);

    const signOut = await handler(request("/v1/auth/sign-out", json({}, session.sessionToken)));
    expect(signOut.status).toBe(204);

    const after = await handler(
      request("/v1/devices/current/push-token", json(alert, session.sessionToken, "PUT")),
    );
    expect(after.status).toBe(401);
  });

  it("opens an anonymous account, links it to Apple, and reports it", async () => {
    // Its own app: the fake verifier signs everyone in as one Apple ID.
    const fresh = setup();
    const { handler } = fresh;
    const accountKey = "k".repeat(43);
    const opened = await handler(request("/v1/auth/anonymous", json({ accountKey })));
    expect(opened.status).toBe(200);
    expect(opened.headers.get("cache-control")).toBe("no-store");
    const session = Schema.decodeUnknownSync(SessionResponse)(await opened.json());

    const account = (token: string) =>
      handler(
        request("/v1/account", { method: "GET", headers: { authorization: `Bearer ${token}` } }),
      );
    expect(await (await account(session.sessionToken)).json()).toEqual({
      userId: session.userId,
      linked: false,
    });

    const challenge = Schema.decodeUnknownSync(AuthChallengeResponse)(
      await (await handler(request("/v1/auth/challenge"))).json(),
    );
    const linked = await handler(
      request(
        "/v1/auth/apple/link",
        json({ identityToken: challenge.nonce }, session.sessionToken),
      ),
    );
    expect(linked.status).toBe(200);
    expect(await linked.json()).toEqual({ userId: session.userId, linked: true });
    expect(await (await account(session.sessionToken)).json()).toEqual({
      userId: session.userId,
      linked: true,
    });

    // The same key on another phone returns to the same account.
    const again = Schema.decodeUnknownSync(SessionResponse)(
      await (await handler(request("/v1/auth/anonymous", json({ accountKey })))).json(),
    );
    expect(again.userId).toBe(session.userId);
    await fresh.dispose();
  });

  it("answers 409 when the Apple ID is linked to another account", async () => {
    const { session: owner } = await signIn(handler);
    const other = Schema.decodeUnknownSync(SessionResponse)(
      await (
        await handler(request("/v1/auth/anonymous", json({ accountKey: "o".repeat(43) })))
      ).json(),
    );
    expect(other.userId).not.toBe(owner.userId);
    const challenge = Schema.decodeUnknownSync(AuthChallengeResponse)(
      await (await handler(request("/v1/auth/challenge"))).json(),
    );
    const response = await handler(
      request("/v1/auth/apple/link", json({ identityToken: challenge.nonce }, other.sessionToken)),
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ _tag: "AppleIdInUse" });
  });

  it("checks the session before reading a link request's body", async () => {
    verifyCalls = 0;
    const response = await handler(
      request("/v1/auth/apple/link", json({ identityToken: "x" }, "x".repeat(43))),
    );
    expect(response.status).toBe(401);
    expect(verifyCalls).toBe(0);
  });

  it.each([
    ["a short key", { accountKey: "short" }],
    ["no key", {}],
  ])("answers 400 or 401 for %s, and opens nothing", async (_name, body) => {
    const response = await handler(request("/v1/auth/anonymous", json(body)));
    expect([400, 401]).toContain(response.status);
  });

  it("marks a challenge as not cacheable", async () => {
    const response = await handler(request("/v1/auth/challenge"));
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
  });

  it("answers a rejected identity token with a bare 401", async () => {
    const response = await handler(request("/v1/auth/apple", json({ identityToken: "bad" })));
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ _tag: "Unauthorized" });
  });

  it("answers 503, not a session, when Apple's keys are unavailable", async () => {
    const response = await handler(
      request("/v1/auth/apple", json({ identityToken: "apple-down" })),
    );
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ _tag: "Unavailable" });
  });

  it.each([
    ["a missing field", "{}"],
    ["broken JSON", "{"],
    ["an empty token", JSON.stringify({ identityToken: "" })],
  ])("answers 400 for %s", async (_name, body) => {
    const response = await handler(request("/v1/auth/apple", { body }));
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ _tag: "InvalidRequest" });
  });

  it("refuses an oversized identity token before verifying it", async () => {
    verifyCalls = 0;
    const response = await handler(
      request("/v1/auth/apple", json({ identityToken: "x".repeat(8193) })),
    );
    expect(response.status).toBe(400);
    expect(verifyCalls).toBe(0);
  });

  it.each([
    ["no header", {}],
    ["another scheme", { authorization: "Basic abc" }],
    ["a lowercase scheme", { authorization: `bearer ${"x".repeat(43)}` }],
    ["a malformed token", { authorization: "Bearer short" }],
    ["an unknown token", { authorization: `Bearer ${"x".repeat(43)}` }],
  ])("answers 401 for %s", async (_name, headers) => {
    const response = await handler(request("/v1/auth/sign-out", { headers }));
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ _tag: "Unauthorized" });
  });

  it("checks the session before reading a device request's body", async () => {
    const response = await handler(
      request("/v1/devices/current/push-token", { method: "PUT", body: "{" }),
    );
    expect(response.status).toBe(401);
  });

  it.each([
    ["an unknown kind", { ...alert, kind: "pigeon" }],
    ["an unknown environment", { ...alert, environment: "staging" }],
    ["a token that isn't hex", { ...alert, token: "not-hex" }],
    ["an odd-length token", { ...alert, token: "abc" }],
    ["an oversized token", { ...alert, token: "ab".repeat(257) }],
  ])("answers 400 for %s", async (_name, body) => {
    const { session } = await signIn(handler);
    const response = await handler(
      request("/v1/devices/current/push-token", json(body, session.sessionToken, "PUT")),
    );
    expect(response.status).toBe(400);
  });
});

describe("logging", () => {
  const sinks = ["log", "info", "warn", "error", "debug"] as const;
  const spies = sinks.map((sink) => vi.spyOn(console, sink));
  beforeEach(() => spies.forEach((spy) => spy.mockImplementation(() => undefined)));
  afterEach(() => spies.forEach((spy) => spy.mockReset()));
  afterAll(() => spies.forEach((spy) => spy.mockRestore()));

  it("records failures without any token, even with the request logger on", async () => {
    const memory = makeInMemoryAuthRepository();
    const app = HttpRouter.toWebHandler(
      AuthRoutes.pipe(
        Layer.provide(AuthService.layer),
        Layer.provide(
          Layer.mergeAll(
            Layer.succeed(AuthRepository, memory.repository),
            Layer.succeed(AuthEngine, makeInMemoryAuthEngine().engine),
            FakeIdentityVerifier,
            Digest.layerWebCrypto,
            SecureRandom.layerWebCrypto,
          ),
        ),
      ),
    );
    const { session } = await signIn(app.handler);
    await app.handler(request("/v1/auth/apple", json({ identityToken: "bad-secret-identity" })));
    await app.handler(request("/v1/auth/apple", json({ identityToken: "apple-down" })));
    await app.handler(
      request("/v1/devices/current/push-token", json(alert, session.sessionToken, "PUT")),
    );
    await app.handler(
      request("/v1/auth/sign-out", {
        headers: { authorization: `Bearer ${"s".repeat(43)}` },
      }),
    );
    await app.dispose();

    const logged = JSON.stringify(spies.flatMap((spy) => spy.mock.calls));
    expect(logged).toContain("auth rejected");
    expect(logged).toContain("auth unavailable");
    for (const secret of [
      session.sessionToken,
      "bad-secret-identity",
      "s".repeat(43),
      alert.token,
    ]) {
      expect(logged).not.toContain(secret);
    }
  });
});
