import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { SchoolResponse } from "@billet/contracts-http-api/school";
import { routes, type Route } from "@billet/contracts-http-api/routes";
import { SchoolRoutes } from "../src/school-routes.ts";
import { SchoolService } from "../src/school-service.ts";
import { makeWorld, pair, user } from "./fake-world.ts";

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
    authenticate: (token) =>
      Effect.succeed({
        userId: user(Redacted.value(token).replace(/x+$/, "")),
        deviceId: Schema.decodeSync(DeviceId)("device"),
        sessionHash: "hash",
      } satisfies Principal),
  }),
);

const world = makeWorld([[pair("pair-a"), user("ana"), user("ben")]]);

const { handler, dispose } = HttpRouter.toWebHandler(
  SchoolRoutes.pipe(
    Layer.provide(Layer.mergeAll(FakeAuth, SchoolService.layer)),
    Layer.provide(world.layer),
  ),
  { disableLogger: true },
);

afterAll(dispose);

const call = async (name: string, route: Route, path: string, body?: unknown) => {
  const response = await handler(
    new Request(`http://billet.test${path}`, {
      method: route.method,
      headers: { authorization: `Bearer ${tokenOf(name)}` },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }),
  );
  return {
    status: response.status,
    cache: response.headers.get("cache-control"),
    json: response.status === 200 ? ((await response.json()) as unknown) : undefined,
  };
};

const view = (name: string) => call(name, routes.getSchool, routes.getSchool.path);
const teach = (name: string, trick: string, stars: number) =>
  call(name, routes.teachTrick, routes.teachTrick.path, { trick, stars });
const send = (name: string, tricks: ReadonlyArray<string>) =>
  call(name, routes.sendRoutine, routes.sendRoutine.path, {
    steps: tricks.map((trick) => ({ trick, landed: true })),
  });
const parsed = (json: unknown) => Schema.decodeUnknownSync(SchoolResponse)(json);

// The cases run in order on one world.
describe("the school routes", () => {
  it("answer what the cat knows to both partners, kept out of caches", async () => {
    const taught = await teach("ana", "spin", 1);
    expect(taught).toMatchObject({ status: 200, cache: "no-store" });
    expect(parsed(taught.json).tricks).toMatchObject([{ trick: "spin", stars: 1, by: "ana" }]);
    expect(parsed((await teach("ana", "spin", 1)).json).tricks).toHaveLength(1);
    const raised = parsed((await teach("ben", "spin", 2)).json);
    expect(raised.tricks).toMatchObject([{ trick: "spin", stars: 2, by: "ana" }]);
  });

  it("carry a routine to the partner", async () => {
    expect((await send("ana", ["spin", "spin", "spin"])).status).toBe(200);
    const seen = parsed((await view("ben")).json);
    expect(seen.partner?.steps.map((step) => step.trick)).toEqual(["spin", "spin", "spin"]);
    expect(seen.mine).toBeUndefined();
  });

  it("refuse a skipped star, an unknown trick in a routine, bad shapes and a stranger", async () => {
    expect((await teach("ana", "sit", 2)).status).toBe(400);
    expect((await teach("ana", "spin", 4)).status).toBe(400);
    expect((await teach("ana", "Not An Id", 1)).status).toBe(400);
    expect((await send("ana", ["spin", "sit", "spin"])).status).toBe(400);
    expect((await send("ana", ["spin", "spin"])).status).toBe(400);
    expect((await send("ana", ["spin", "spin", "spin", "spin", "spin", "spin"])).status).toBe(400);
    expect((await view("stranger")).status).toBe(404);
  });
});
