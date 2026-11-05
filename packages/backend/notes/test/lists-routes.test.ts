import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { ListsResponse } from "@billet/contracts-http-api/lists";
import { ListsRoutes } from "../src/lists-routes.ts";
import { ListsService } from "../src/lists-service.ts";
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
  ListsRoutes.pipe(
    Layer.provide(Layer.mergeAll(FakeAuth, ListsService.layer)),
    Layer.provide(world.layer),
  ),
  { disableLogger: true },
);

afterAll(dispose);

const call = async (method: string, name: string, body?: unknown) => {
  const response = await handler(
    new Request("http://billet.test/v1/lists", {
      method,
      headers: { authorization: `Bearer ${tokenOf(name)}` },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }),
  );
  return {
    status: response.status,
    cache: response.headers.get("cache-control"),
    lists:
      response.status === 200
        ? Schema.decodeUnknownSync(ListsResponse)(await response.json()).lists
        : undefined,
  };
};

const list = "00000000-0000-4000-8000-0000000000b1";
const item = "00000000-0000-4000-8000-0000000000b2";
let keys = 0;
const key = () => `00000000-0000-4000-8000-${String((keys += 1)).padStart(12, "0")}`;

// The cases run in order on one world.
describe("the list routes", () => {
  it("opens the room on the first call and keeps every answer out of caches", async () => {
    expect(await call("GET", "ana")).toEqual({ status: 200, cache: "no-store", lists: [] });
  });

  it("shows one partner's list and item to the other", async () => {
    const create = {
      _tag: "CreateList",
      key: key(),
      list,
      kind: "groceries",
      title: "Groceries",
      icon: { symbol: "cart", tint: "sage" },
    };
    expect((await call("POST", "ana", { change: create })).status).toBe(200);
    const added = await call("POST", "ana", {
      change: { _tag: "AddItem", key: key(), list, item, text: "Oat milk", quantity: "2" },
      utcOffsetSeconds: 3600,
    });
    expect(added.lists?.[0]?.items).toEqual([
      expect.objectContaining({ id: item, text: "Oat milk", quantity: "2", author: "ana" }),
    ]);
    const other = await call("GET", "ben");
    expect(other.lists?.[0]).toMatchObject({ id: list, title: "Groceries" });
  });

  it("refuses a change to a list or item that is gone, a stranger, and a bad body", async () => {
    const gone = "00000000-0000-4000-8000-0000000000ff";
    expect(
      (await call("POST", "ben", { change: { _tag: "TickItem", key: key(), list: gone, item } }))
        .status,
    ).toBe(404);
    expect(
      (await call("POST", "ben", { change: { _tag: "TickItem", key: key(), list, item: gone } }))
        .status,
    ).toBe(404);
    expect((await call("GET", "stranger")).status).toBe(404);
    expect((await call("POST", "ana", { change: { _tag: "Nope" } })).status).toBe(400);
  });
});
