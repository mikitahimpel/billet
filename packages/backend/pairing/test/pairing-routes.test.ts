import { Effect, Layer, Redacted, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthRejected, AuthUnavailable } from "@billet/backend-auth/auth-error";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { ClaimInviteResponse, CreateInviteResponse } from "@billet/contracts-http-api/invite";
import { PairingObserver } from "../src/pairing-observer.ts";
import { PairingRepository } from "../src/pairing-repository.ts";
import { PairingRoutes } from "../src/pairing-routes.ts";
import { PairingService } from "../src/pairing-service.ts";
import { PairingUnavailable } from "../src/pairing-error.ts";
import { makeInMemoryPairingRepository } from "./in-memory-pairing-repository.ts";

const tokenOf = (name: string) => name.padEnd(43, "x");

const principal = (token: string): Principal => ({
  userId: Schema.decodeSync(UserId)(token),
  deviceId: Schema.decodeSync(DeviceId)(`device-${token}`),
  sessionHash: `hash-${token}`,
});

const FakeAuth = Layer.succeed(
  AuthService,
  AuthService.of({
    issueChallenge: Effect.die("unused"),
    signInAnonymously: () => Effect.die("unused"),
    signInWithApple: () => Effect.die("unused"),
    linkApple: () => Effect.die("unused"),
    account: () => Effect.die("unused"),
    signOut: () => Effect.die("unused"),
    registerPushToken: () => Effect.die("unused"),
    authenticate: (token) => {
      const raw = Redacted.value(token);
      if (raw.startsWith("rejected")) return Effect.fail(new AuthRejected({ reason: "fake" }));
      if (raw.startsWith("down")) return Effect.fail(new AuthUnavailable({ reason: "fake" }));
      return Effect.succeed(principal(raw));
    },
  }),
);

const setup = (repository: PairingRepository["Service"]) =>
  HttpRouter.toWebHandler(
    PairingRoutes.pipe(
      Layer.provide(Layer.mergeAll(FakeAuth, PairingService.layer)),
      Layer.provide(
        Layer.mergeAll(
          Layer.succeed(PairingRepository, repository),
          PairingObserver.silent,
          Digest.layerWebCrypto,
          SecureRandom.layerWebCrypto,
        ),
      ),
    ),
    { disableLogger: true },
  );

const request = (path: string, name: string, init: RequestInit = {}) =>
  new Request(`http://billet.test${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${tokenOf(name)}`, "content-type": "application/json" },
    ...init,
  });

describe("pairing routes", () => {
  const app = setup(makeInMemoryPairingRepository().repository);
  const { handler } = app;
  afterAll(() => app.dispose());

  const invite = async (name: string) => {
    const response = await handler(request("/v1/invites", name));
    return { response, ...Schema.decodeUnknownSync(CreateInviteResponse)(await response.json()) };
  };

  const claim = (name: string, code: string) =>
    handler(request("/v1/invites/claim", name, { body: JSON.stringify({ code }) }));

  const unpair = (name: string) => handler(request("/v1/pair", name, { method: "DELETE" }));

  it("runs the whole flow: invite, claim, unpair, invite again", async () => {
    const { response, code } = await invite("ana");
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");

    const claimed = await claim("ben", code);
    expect(claimed.status).toBe(200);
    Schema.decodeUnknownSync(ClaimInviteResponse)(await claimed.json());

    expect((await unpair("ben")).status).toBe(204);
    expect((await unpair("ben")).status).toBe(204);
    expect((await invite("ana")).response.status).toBe(200);
  });

  it("names the caller's pair and both members, the caller first, and 404 once it ends", async () => {
    const { code } = await invite("hal");
    const claimed = Schema.decodeUnknownSync(ClaimInviteResponse)(
      await (await claim("ivy", code)).json(),
    );
    const pair = (name: string) => handler(request("/v1/pair", name, { method: "GET" }));
    const seen = await pair("hal");
    expect(seen.status).toBe(200);
    expect(seen.headers.get("cache-control")).toBe("no-store");
    expect(await seen.json()).toEqual({
      pairId: claimed.pairId,
      members: [tokenOf("hal"), tokenOf("ivy")],
    });
    expect(await (await pair("ivy")).json()).toMatchObject({
      members: [tokenOf("ivy"), tokenOf("hal")],
    });
    await unpair("hal");
    expect((await pair("ivy")).status).toBe(404);
  });

  it("answers 404 InvalidInvite for a code nobody issued", async () => {
    const response = await claim("cal", "ABCD2345EF");
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ _tag: "InvalidInvite" });
  });

  it("answers 409 AlreadyPaired to a paired caller", async () => {
    const { code } = await invite("dee");
    await claim("eve", code);
    const other = await invite("fay");

    const claimed = await claim("eve", other.code);
    expect(claimed.status).toBe(409);
    expect(await claimed.json()).toEqual({ _tag: "AlreadyPaired" });

    const invited = await handler(request("/v1/invites", "eve"));
    expect(invited.status).toBe(409);
    expect(await invited.json()).toEqual({ _tag: "AlreadyPaired" });
  });

  it.each([
    ["a missing field", "{}"],
    ["broken JSON", "{"],
    ["a short code", JSON.stringify({ code: "ABC" })],
    ["a lowercase code", JSON.stringify({ code: "abcd2345ef" })],
    ["a symbol outside the alphabet", JSON.stringify({ code: "ABCD2345E0" })],
  ])("answers 400 for %s", async (_name, body) => {
    const response = await handler(request("/v1/invites/claim", "gia", { body }));
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ _tag: "InvalidRequest" });
  });

  it.each([
    ["POST", "/v1/invites"],
    ["POST", "/v1/invites/claim"],
    ["DELETE", "/v1/pair"],
  ])("checks the session first on %s %s", async (method, path) => {
    const rejected = await handler(
      request(path, "rejected", { method, body: method === "POST" ? "{" : null }),
    );
    expect(rejected.status).toBe(401);
    const down = await handler(
      request(path, "down", { method, body: method === "POST" ? "{" : null }),
    );
    expect(down.status).toBe(503);
  });
});

describe("pairing routes without storage", () => {
  const down = Effect.fail(new PairingUnavailable({ reason: "fake" }));
  const app = setup({
    saveInvite: () => down,
    claimInvite: () => down,
    findPair: () => down,
    pairedAt: () => down,
    findMembers: () => down,
    unpair: () => down,
  });
  afterAll(() => app.dispose());

  it.each([
    ["POST", "/v1/invites", undefined],
    ["POST", "/v1/invites/claim", JSON.stringify({ code: "ABCD2345EF" })],
    ["DELETE", "/v1/pair", undefined],
  ])("answers 503 on %s %s", async (method, path, body) => {
    const response = await app.handler(request(path, "ana", { method, body: body ?? null }));
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ _tag: "Unavailable" });
  });
});
