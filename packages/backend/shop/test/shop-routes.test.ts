import { Schema } from "effect";
import { Layer } from "effect";
import { Digest } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { routes } from "@billet/contracts-http-api/routes";
import { ShopCatalogResponse } from "@billet/contracts-http-api/shop";
import { Effect } from "effect";
import { ShopArt } from "../src/shop-art.ts";
import { ShopCatalogRoutes } from "../src/shop-routes.ts";
import { ShopStore } from "../src/shop-store.ts";
import { seedItems } from "../src/shop-seed.ts";
import { InMemoryShopArt } from "./in-memory-shop-art.ts";
import { InMemoryShopStore } from "./in-memory-shop-store.ts";

const store = InMemoryShopStore();
const art = InMemoryShopArt();
const { handler, dispose } = HttpRouter.toWebHandler(
  ShopCatalogRoutes.pipe(Layer.provide(Layer.mergeAll(store, art, Digest.layerWebCrypto))),
  { disableLogger: true },
);
afterAll(() => dispose());

const get = (path: string, headers: Record<string, string> = {}) =>
  handler(new Request(`http://billet.test${path}`, { headers }));

describe("the shop catalog route", () => {
  it("serves the active items without a session, cacheable, with a hash of them as the ETag", async () => {
    const response = await get(routes.getShopCatalog.path);
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("public, max-age=60");
    const body = Schema.decodeUnknownSync(ShopCatalogResponse)(await response.json());
    expect(response.headers.get("etag")).toBe(`"${body.version}"`);
    expect(body.items).toEqual(seedItems);
  });

  it("answers 304 with no body to a caller that has this version", async () => {
    const first = await get(routes.getShopCatalog.path);
    const etag = first.headers.get("etag") ?? "";
    for (const tag of [etag, `W/${etag}`, "*", `"x", ${etag}`]) {
      const response = await get(routes.getShopCatalog.path, { "if-none-match": tag });
      expect(response.status, tag).toBe(304);
      expect(await response.text()).toBe("");
    }
    expect((await get(routes.getShopCatalog.path, { "if-none-match": '"other"' })).status).toBe(
      200,
    );
  });

  it("changes its version when an item changes, and leaves an inactive item out", async () => {
    const before = (await get(routes.getShopCatalog.path)).headers.get("etag");
    const lamp = seedItems.find((item) => item.id === "lamp");
    if (lamp === undefined) throw new Error("no lamp");
    await Effect.runPromise(
      Effect.gen(function* () {
        const shop = yield* ShopStore;
        yield* shop.update({
          item: { ...lamp, price: 150 },
          active: false,
          expectedVersion: 1,
          by: "a",
          at: 1,
        });
      }).pipe(Effect.provide(store)),
    );
    const response = await get(routes.getShopCatalog.path);
    expect(response.headers.get("etag")).not.toBe(before);
    const body = Schema.decodeUnknownSync(ShopCatalogResponse)(await response.json());
    expect(body.items.some((item) => item.id === "lamp")).toBe(false);
  });
});

describe("the shop art route", () => {
  it("serves an uploaded picture forever, and 404s anything else", async () => {
    const bytes = new Uint8Array([1, 2, 3]);
    await Effect.runPromise(
      Effect.gen(function* () {
        const files = yield* ShopArt;
        yield* files.put("0123456789abcdef.webp", bytes, "image/webp");
      }).pipe(Effect.provide(art)),
    );
    const found = await get("/v1/shop/art/0123456789abcdef.webp");
    expect(found.status).toBe(200);
    expect(found.headers.get("content-type")).toBe("image/webp");
    expect(found.headers.get("cache-control")).toContain("immutable");
    expect(new Uint8Array(await found.arrayBuffer())).toEqual(bytes);
    expect((await get("/v1/shop/art/ffffffffffffffff.webp")).status).toBe(404);
    expect((await get("/v1/shop/art/..%2Fsecret")).status).toBe(404);
    expect((await get("/v1/shop/art/notakey.webp")).status).toBe(404);
  });
});
