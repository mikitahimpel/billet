import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthRejected } from "@billet/backend-auth/auth-error";
import { AuthService } from "@billet/backend-auth/auth-service";
import { AlreadyPaired } from "@billet/backend-pairing/pairing-error";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PairResponse } from "@billet/contracts-http-api/pair";
import { DemoPartnerUnavailable, NoDemoPartner } from "../src/demo-partner-error.ts";
import { DemoPartnerRoutes } from "../src/demo-partner-routes.ts";
import { DemoPartnerService } from "../src/demo-partner-service.ts";

const user = Schema.decodeSync(UserId);
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
        userId: user(raw.slice(0, raw.indexOf("x"))),
        deviceId: Schema.decodeSync(DeviceId)(`device-${raw}`),
        sessionHash: `hash-${raw}`,
      });
    },
  }),
);

const pair = { pairId: Schema.decodeSync(PairId)("pair-1"), members: [user("ana"), user("bot")] };

// Each caller's name decides the answer: the service is the one under test elsewhere.
const FakeDemo = Layer.succeed(
  DemoPartnerService,
  DemoPartnerService.of({
    create: (ownerId) => {
      if (ownerId === "paired") return Effect.fail(new AlreadyPaired());
      if (ownerId === "down") return Effect.fail(new DemoPartnerUnavailable({ reason: "fake" }));
      return Effect.succeed({ ...pair, members: [ownerId, user("bot")] });
    },
    status: (ownerId) => Effect.succeed({ paired: ownerId === "ana" }),
    remove: (ownerId) => (ownerId === "alone" ? Effect.fail(new NoDemoPartner()) : Effect.void),
  }),
);

const app = HttpRouter.toWebHandler(
  DemoPartnerRoutes.pipe(Layer.provide(Layer.mergeAll(FakeAuth, FakeDemo))),
  { disableLogger: true },
);
afterAll(() => app.dispose());

const send = (method: string, name: string) =>
  app.handler(
    new Request("http://billet.test/v1/dev/demo-partner", {
      method,
      headers: { authorization: `Bearer ${tokenOf(name)}` },
    }),
  );

describe("demo partner routes", () => {
  it("answers the new pair, the caller first", async () => {
    const response = await send("POST", "ana");
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(Schema.decodeUnknownSync(PairResponse)(await response.json())).toEqual(pair);
  });

  it.each([
    ["POST", "paired", 409, { _tag: "AlreadyPaired" }],
    ["POST", "down", 503, { _tag: "Unavailable" }],
    ["DELETE", "alone", 404, { _tag: "NotFound" }],
  ])("answers %s by %s with %i", async (method, name, status, body) => {
    const response = await send(method, name);
    expect(response.status).toBe(status);
    expect(await response.json()).toEqual(body);
  });

  it.each([
    ["ana", true],
    ["alone", false],
  ])("tells %s whether they are paired with their bot", async (name, paired) => {
    const response = await send("GET", name);
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.json()).toEqual({ paired });
  });

  it("deletes with no body", async () => {
    const response = await send("DELETE", "ana");
    expect(response.status).toBe(204);
    expect(await response.text()).toBe("");
  });

  it.each([["POST"], ["GET"], ["DELETE"]])("refuses %s without a session", async (method) => {
    expect((await send(method, "rejected")).status).toBe(401);
  });
});
