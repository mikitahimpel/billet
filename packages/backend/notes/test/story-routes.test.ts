import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { StoryResponse } from "@billet/contracts-http-api/story";
import { routes, type Route } from "@billet/contracts-http-api/routes";
import { StoryRoutes } from "../src/story-routes.ts";
import { StoryService } from "../src/story-service.ts";
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
  StoryRoutes.pipe(
    Layer.provide(Layer.mergeAll(FakeAuth, StoryService.layer)),
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

const view = (name: string) => call(name, routes.getStory, routes.getStory.path);
const mark = (name: string, kind: string, ref: string, episode = "fish-plush") =>
  call(name, routes.markStory, routes.markStory.path, { episode, kind, ref });
const parsed = (json: unknown) => Schema.decodeUnknownSync(StoryResponse)(json);

// The cases run in order on one world.
describe("the story routes", () => {
  it("answer the caller's own marks, kept out of caches", async () => {
    const found = await mark("ana", "found", "empty-basket");
    expect(found).toMatchObject({ status: 200, cache: "no-store" });
    expect(parsed(found.json).mine).toMatchObject([{ kind: "found", ref: "empty-basket" }]);
    expect(parsed((await mark("ana", "found", "empty-basket")).json).mine).toHaveLength(1);
    expect(parsed((await view("ben")).json).partner).toHaveLength(1);
  });

  it("hold a partner's suspect back until the caller names one, and keep the first", async () => {
    await mark("ana", "named", "crow");
    await mark("ana", "named", "snail");
    expect(parsed((await view("ben")).json).partner.map((m) => m.ref)).toEqual(["empty-basket"]);
    const both = parsed((await mark("ben", "named", "snail")).json);
    expect(both.partner.map((m) => m.ref)).toEqual(["empty-basket", "crow"]);
  });

  it("refuse a malformed mark, a stranger, and the mark past the limit", async () => {
    expect((await mark("ana", "found", "Not An Id")).status).toBe(400);
    expect((await mark("ana", "guessed", "crow")).status).toBe(400);
    expect((await view("stranger")).status).toBe(404);
    for (let beat = 0; beat < 40; beat++) await mark("ben", "found", `beat-${beat}`, "long");
    expect((await mark("ben", "found", "beat-40", "long")).status).toBe(400);
    expect((await mark("ben", "found", "beat-1", "long")).status).toBe(200);
  });
});
