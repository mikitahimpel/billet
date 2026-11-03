import { Effect, Layer, Option, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthRejected } from "@billet/backend-auth/auth-error";
import { AuthService } from "@billet/backend-auth/auth-service";
import { DeviceId, type UserId, UserId as UserIdSchema } from "@billet/contracts-domain/ids";
import { AccountDeletion } from "../src/account-deletion.ts";
import { AccountUnavailable } from "../src/account-error.ts";
import { AccountRoutes } from "../src/account-routes.ts";

const tokenOf = (name: string) => name.padEnd(43, "x");

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
      return Effect.succeed({
        userId: Schema.decodeSync(UserIdSchema)(raw.replace(/x+$/, "")),
        deviceId: Schema.decodeSync(DeviceId)(`device-${raw}`),
        sessionHash: `hash-${raw}`,
      });
    },
  }),
);

const calls: Array<{ userId: UserId; code: Option.Option<string> }> = [];

const FakeDeletion = Layer.succeed(AccountDeletion, {
  deleteAccount: (userId, code) =>
    userId === "down"
      ? Effect.fail(new AccountUnavailable({ reason: "notes-unavailable" }))
      : Effect.sync(() => void calls.push({ userId, code: Option.map(code, Redacted.value) })),
});

const request = (name: string, body?: unknown) =>
  new Request("http://billet.test/v1/account", {
    method: "DELETE",
    headers: { authorization: `Bearer ${tokenOf(name)}`, "content-type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });

describe("account routes", () => {
  const app = HttpRouter.toWebHandler(
    AccountRoutes.pipe(Layer.provide(Layer.mergeAll(FakeAuth, FakeDeletion))),
    { disableLogger: true },
  );
  const { handler } = app;
  afterAll(() => app.dispose());

  it("deletes the caller's account, passing on the Apple code", async () => {
    calls.length = 0;
    expect((await handler(request("ana", {}))).status).toBe(204);
    expect((await handler(request("ben", { appleAuthorizationCode: "code-1" }))).status).toBe(204);
    expect(calls).toEqual([
      { userId: "ana", code: Option.none() },
      { userId: "ben", code: Option.some("code-1") },
    ]);
  });

  it("checks the caller before the body", async () => {
    calls.length = 0;
    expect((await handler(request("rejected", { nonsense: 1 }))).status).toBe(401);
    expect(calls).toEqual([]);
  });

  it("refuses a malformed body", async () => {
    calls.length = 0;
    expect((await handler(request("ana", { appleAuthorizationCode: "" }))).status).toBe(400);
    expect((await handler(request("ana"))).status).toBe(400);
    expect(calls).toEqual([]);
  });

  it("answers 503 when a step fails, so the app tries again", async () => {
    const response = await handler(request("down", {}));
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ _tag: "Unavailable" });
  });
});
