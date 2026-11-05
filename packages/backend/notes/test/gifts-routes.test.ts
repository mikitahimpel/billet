import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { GiftsResponse } from "@billet/contracts-http-api/gifts";
import { GiftsRoutes } from "../src/gifts-routes.ts";
import { GiftsService } from "../src/gifts-service.ts";
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
  GiftsRoutes.pipe(
    Layer.provide(Layer.mergeAll(FakeAuth, GiftsService.layer)),
    Layer.provide(world.layer),
  ),
  { disableLogger: true },
);

afterAll(dispose);

const call = async (method: string, path: string, name: string, body?: unknown) => {
  const response = await handler(
    new Request(`http://billet.test${path}`, {
      method,
      headers: { authorization: `Bearer ${tokenOf(name)}` },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }),
  );
  return {
    status: response.status,
    cache: response.headers.get("cache-control"),
    gifts:
      response.status === 200
        ? Schema.decodeUnknownSync(GiftsResponse)(await response.json())
        : undefined,
  };
};

const id = "00000000-0000-4000-8000-0000000000a1";
const wish = { id, title: "Bracelet", link: "", price: "$65", note: "silver", mostWanted: true };

// The cases run in order on one world.
describe("the gift routes", () => {
  it("opens the room on the first call and keeps every answer out of caches", async () => {
    const first = await call("GET", "/v1/gifts", "ana");
    expect(first).toMatchObject({ status: 200, cache: "no-store" });
    expect(first.gifts).toEqual({ wishes: [], plans: [], surprise: false, loves: [] });
  });

  it("shows the owner's wish to both, but the giver's plan only to the giver", async () => {
    expect((await call("PUT", "/v1/gifts/wishes", "ana", wish)).status).toBe(200);
    const giver = await call("PUT", "/v1/gifts/plans", "ben", { wish: id, stage: "planning" });
    expect(giver.gifts?.plans).toEqual([{ wish: id, stage: "planning" }]);

    const owner = await call("GET", "/v1/gifts", "ana");
    expect(owner.gifts?.wishes).toEqual([
      expect.objectContaining({ id, owner: "ana", note: "silver" }),
    ]);
    expect(owner.gifts?.plans).toEqual([]);
    expect(owner.gifts?.surprise).toBe(true);
  });

  it("refuses what is not the caller's to change, and a wish that is not there", async () => {
    expect((await call("PUT", "/v1/gifts/wishes", "ben", { ...wish, title: "Mine" })).status).toBe(
      400,
    );
    expect(
      (await call("PUT", "/v1/gifts/plans", "ana", { wish: id, stage: "bought" })).status,
    ).toBe(400);
    expect(
      (await call("PUT", "/v1/gifts/received", "ben", { wish: id, received: true })).status,
    ).toBe(400);
    expect(
      (
        await call("DELETE", "/v1/gifts/wishes", "ana", {
          id: "00000000-0000-4000-8000-0000000000ff",
        })
      ).status,
    ).toBe(404);
    expect((await call("GET", "/v1/gifts", "stranger")).status).toBe(404);
  });

  it("names the giver once the owner says it arrived", async () => {
    const received = await call("PUT", "/v1/gifts/received", "ana", { wish: id, received: true });
    expect(received.gifts?.wishes[0]).toMatchObject({ giftedBy: "ben" });
    expect(received.gifts?.surprise).toBe(false);
  });

  it("keeps each partner's What I love", async () => {
    const loves = {
      sizes: "S",
      flowers: "Peonies",
      coffee: "",
      sweets: "",
      allergies: "",
      avoid: "Lilies",
    };
    await call("PUT", "/v1/gifts/loves", "ana", { loves });
    expect((await call("GET", "/v1/gifts", "ben")).gifts?.loves).toEqual([{ user: "ana", loves }]);
  });
});
