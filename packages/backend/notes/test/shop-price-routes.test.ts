import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { welcomeCoins } from "@billet/contracts-domain/shop";
import { OrderResponse, ShopResponse } from "@billet/contracts-http-api/shop";
import { seedItems } from "@billet/backend-shop/shop-seed";
import { ShopStore } from "@billet/backend-shop/shop-store";
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

const world = makeWorld([[pair("pair-a"), user("ana"), user("ben")]]);

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

let keys = 0;
const newKey = () => `00000000-0000-4000-9000-${String((keys += 1)).padStart(12, "0")}`;

/** The admin's side: what the panel does to the same store the Worker reads. */
const admin = <A, E>(use: (store: ShopStore["Service"]) => Effect.Effect<A, E>) =>
  Effect.runPromise(ShopStore.use(use).pipe(Effect.provide(world.layer)));

const entry = (id: string) => {
  const found = seedItems.find((item) => item.id === id);
  if (found === undefined) throw new Error(`no ${id}`);
  return found;
};

const orderItem = (item: string, expectedPrice?: number, name = "ana") =>
  call("POST", "/v1/shop/orders", name, {
    id: newKey(),
    offer: { _tag: "Item", item },
    ...(expectedPrice === undefined ? {} : { expectedPrice }),
  });

describe("an order is priced by the server's catalog", () => {
  it("charges the catalog price, whatever the app's price was, when it was not higher", async () => {
    const response = await orderItem("monstera", 200);
    expect(response.status).toBe(200);
    const bought = Schema.decodeUnknownSync(OrderResponse)(await response.json());
    expect(bought.entry.amount).toBe(-90);
    expect(bought.shop.balance).toBe(welcomeCoins - 90);
  });

  it("refuses an order whose price rose after the buyer saw it, charging nothing", async () => {
    const yarn = entry("yarn");
    await admin((store) =>
      store.update({
        item: { ...yarn, price: 80 },
        active: true,
        expectedVersion: 1,
        by: "owner@example.com",
        at: 1,
      }),
    );
    const refused = await orderItem("yarn", 60);
    expect(refused.status).toBe(409);
    expect(await refused.json()).toEqual({ _tag: "PriceChanged", price: 80 });
    const shop = Schema.decodeUnknownSync(ShopResponse)(
      await (await call("GET", "/v1/shop", "ana")).json(),
    );
    expect(shop.balance).toBe(welcomeCoins - 90);
    expect(shop.items).not.toContain("yarn");
    // The buyer asks again with the new price and pays it.
    const again = Schema.decodeUnknownSync(OrderResponse)(
      await (await orderItem("yarn", 80)).json(),
    );
    expect(again.entry.amount).toBe(-80);
  });

  it("charges the lower price when the price fell", async () => {
    const mouse = entry("mouse");
    await admin((store) =>
      store.update({
        item: { ...mouse, price: 30 },
        active: true,
        expectedVersion: 1,
        by: "owner@example.com",
        at: 1,
      }),
    );
    const bought = Schema.decodeUnknownSync(OrderResponse)(
      await (await orderItem("mouse", 45)).json(),
    );
    expect(bought.entry.amount).toBe(-30);
  });

  it("does not sell an inactive item, and leaves what the pair already owns", async () => {
    const lantern = entry("lantern");
    await admin((store) =>
      store.update({
        item: lantern,
        active: false,
        expectedVersion: 1,
        by: "owner@example.com",
        at: 1,
      }),
    );
    expect((await orderItem("lantern", 150)).status).toBe(404);
    const shop = Schema.decodeUnknownSync(ShopResponse)(
      await (await call("GET", "/v1/shop", "ana")).json(),
    );
    expect(shop.items).toEqual(expect.arrayContaining(["monstera", "yarn", "mouse"]));
  });

  it("sells an item the admin created, though the app's list has never heard of it", async () => {
    await admin((store) =>
      store.create({
        item: {
          ...entry("print"),
          id: "paper-moon",
          name: "Paper Moon",
          price: 25,
          sortOrder: 5,
        },
        active: true,
        by: "owner@example.com",
        at: 1,
      }),
    );
    const bought = Schema.decodeUnknownSync(OrderResponse)(
      await (await orderItem("paper-moon", 25)).json(),
    );
    expect(bought.shop.items).toContain("paper-moon");
  });
});
