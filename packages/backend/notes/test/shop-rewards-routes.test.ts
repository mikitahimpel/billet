import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { collectionOf, starterItems, welcomeCoins } from "@billet/contracts-domain/shop";
import { CoinsResponse, EarnResponse } from "@billet/contracts-http-api/coins";
import { ClaimBonusResponse, OpenGiftResponse } from "@billet/contracts-http-api/shop";
import { NotesRoutes } from "../src/notes-routes.ts";
import { NotesService } from "../src/notes-service.ts";
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
    authenticate: (token) => {
      const principal: Principal = {
        userId: user(Redacted.value(token).replace(/x+$/, "")),
        deviceId: Schema.decodeSync(DeviceId)("device"),
        sessionHash: "hash",
      };
      return Effect.succeed(principal);
    },
  }),
);

const world = makeWorld([
  [pair("pair-a"), user("ana"), user("ben")],
  [pair("pair-b"), user("cal"), user("dee")],
  [pair("pair-c"), user("fin"), user("gus")],
]);

const { handler, dispose } = HttpRouter.toWebHandler(
  NotesRoutes.pipe(
    Layer.provide(Layer.merge(FakeAuth, NotesService.layer)),
    Layer.provide(world.layer),
  ),
  { disableLogger: true },
);

afterAll(dispose);

const call = (method: string, path: string, name: string, body?: unknown) =>
  handler(
    new Request(`http://billet.test${path}`, {
      method,
      headers: { authorization: `Bearer ${tokenOf(name)}`, "content-type": "application/json" },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }),
  );

const decodeCoins = Schema.decodeUnknownSync(CoinsResponse);
const decodeEarn = Schema.decodeUnknownSync(EarnResponse);
const decodeGift = Schema.decodeUnknownSync(OpenGiftResponse);
const decodeBonus = Schema.decodeUnknownSync(ClaimBonusResponse);

let keys = 0;
const newKey = () => `00000000-0000-4000-9000-${String((keys += 1)).padStart(12, "0")}`;

describe("the coin routes", () => {
  it("open a new pair's room on its first wallet read, with the welcome coins once", async () => {
    const coins = decodeCoins(await (await call("GET", "/v1/coins", "dee")).json());
    expect(coins).toMatchObject({ balance: welcomeCoins });
    const again = decodeCoins(await (await call("GET", "/v1/coins", "cal")).json());
    expect(again.entries.map((entry) => entry.id)).toEqual(["gift:welcome"]);
  });

  it("answer 404 to a caller without a partner", async () => {
    for (const [method, path, body] of [
      ["POST", "/v1/shop/gift", {}],
      ["POST", "/v1/shop/bonus", { collection: "cozy-autumn" }],
      ["POST", "/v1/coins/earn", { event: { _tag: "WishReceived", wish: "w1" } }],
    ] as const) {
      expect((await call(method, path, "eve", body)).status, path).toBe(404);
    }
  });

  it("refuse a treat before the cat is adopted", async () => {
    const treat = await call("POST", "/v1/shop/orders", "ana", {
      id: newKey(),
      offer: { _tag: "Treat" },
    });
    expect(treat.status).toBe(409);
    expect(await treat.json()).toEqual({ _tag: "CatNotAdopted" });
  });

  it("open the day's gift once for both partners, never cached", async () => {
    const first = await call("POST", "/v1/shop/gift", "ana", {});
    expect(first.status).toBe(200);
    expect(first.headers.get("cache-control")).toBe("no-store");
    const opened = decodeGift(await first.json());
    expect(opened.entry.id).toBe(`gift:${opened.shop.giftDay}`);
    const again = await call("POST", "/v1/shop/gift", "ben", {});
    expect(decodeGift(await again.json())).toEqual(opened);
  });

  it("refuse an incomplete collection's bonus", async () => {
    const response = await call("POST", "/v1/shop/bonus", "ana", { collection: "cozy-autumn" });
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      _tag: "CollectionIncomplete",
      collection: "cozy-autumn",
    });
  });

  it("pay an app earn once per ref", async () => {
    const earn = { event: { _tag: "DateRated", plan: "plan-1" }, utcOffsetSeconds: 3600 };
    const first = decodeEarn(await (await call("POST", "/v1/coins/earn", "ana", earn)).json());
    expect(first.entry).toMatchObject({ id: "earn:plan:plan-1", amount: 30 });
    const again = await (await call("POST", "/v1/coins/earn", "ben", earn)).json();
    expect(again).toEqual(first);
  });

  it("pay a complete collection's bonus once, to either partner", async () => {
    // The pieces cost more than the welcome coins, so the pair earns some first.
    for (let n = 0; n < 12; n++) {
      await call("POST", "/v1/coins/earn", "fin", { event: { _tag: "DateRated", plan: `p${n}` } });
    }
    const missing = (collectionOf("cozy-autumn")?.items ?? []).filter(
      (id) => !starterItems.includes(id),
    );
    for (const item of missing) {
      const bought = await call("POST", "/v1/shop/orders", "gus", {
        id: newKey(),
        offer: { _tag: "Item", item },
      });
      expect(bought.status, item).toBe(200);
    }
    const paid = await call("POST", "/v1/shop/bonus", "fin", { collection: "cozy-autumn" });
    expect(paid.status).toBe(200);
    const bonus = decodeBonus(await paid.json());
    expect(bonus).toMatchObject({
      entry: { id: "bonus:cozy-autumn", amount: 150 },
      shop: { bonuses: ["cozy-autumn"] },
    });
    const again = await call("POST", "/v1/shop/bonus", "gus", { collection: "cozy-autumn" });
    expect(decodeBonus(await again.json())).toEqual(bonus);
  });
});
