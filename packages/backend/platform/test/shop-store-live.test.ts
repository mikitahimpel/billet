import { env } from "cloudflare:workers";
import { Effect, Layer, Schema, Scope } from "effect";
import { beforeEach, describe, expect, it } from "vitest";
import { ShopCatalogItem } from "@billet/contracts-domain/shop-catalog";
import { seedItems } from "@billet/backend-shop/shop-seed";
import { ShopStore } from "@billet/backend-shop/shop-store";
import { ShopStoreLive } from "../src/shop-store-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const storeOn = (binding: D1Database) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(ShopStoreLive(binding), yield* Scope.make());
      return context.mapUnsafe.get(ShopStore.key) as ShopStore["Service"];
    }),
  );

const moon = Schema.decodeUnknownSync(ShopCatalogItem)({
  id: "paper-moon",
  kind: "decor",
  name: "Paper Moon",
  rarity: "rare",
  price: 200,
  section: "decor",
  sortOrder: 5,
  asset: { _tag: "Picture", key: "0123456789abcdef.webp" },
  sale: { price: 150, from: 10, until: 20 },
  deal: { discount: 0.5, order: 9 },
  minBuild: 7,
  plus: true,
});

const migrations = import.meta.glob<string>("../migrations/directory/*_shop_items/migration.sql", {
  eager: true,
  import: "default",
});

// The tests change the catalog, and D1's storage is shared between them: each starts from the
// rows the migration inserted.
beforeEach(async () => {
  await resetDirectory();
  const sql = Object.values(migrations)[0] ?? "";
  const seed = sql.split("--> statement-breakpoint").find((part) => part.includes("INSERT INTO"));
  await env.DB.batch([
    env.DB.prepare("DELETE FROM shop_items"),
    env.DB.prepare(seed ?? "SELECT 1"),
  ]);
});

describe("the D1 shop catalog", () => {
  it("is seeded with today's pieces and inks at today's prices, so a deploy changes nothing", async () => {
    const store = await storeOn(env.DB);
    expect(await Effect.runPromise(store.active)).toEqual(seedItems);
    const all = await Effect.runPromise(store.all);
    expect(all.every((entry) => entry.active && entry.version === 1)).toBe(true);
    expect(all.every((entry) => entry.createdBy === "migration")).toBe(true);
  });

  it("creates an item with everything the admin sets, once per id", async () => {
    const store = await storeOn(env.DB);
    const made = await Effect.runPromise(
      store.create({ item: moon, active: true, by: "a@b.c", at: 1_000 }),
    );
    expect(made).toMatchObject({ item: moon, version: 1, createdBy: "a@b.c" });
    const again = await Effect.runPromise(
      Effect.flip(store.create({ item: moon, active: true, by: "a@b.c", at: 1_001 })),
    );
    expect(again._tag).toBe("ShopItemExists");
    const active = await Effect.runPromise(store.active);
    expect(active[0]).toEqual(moon);
  });

  it("saves against the version read, and refuses a stale save without logging it", async () => {
    const store = await storeOn(env.DB);
    await Effect.runPromise(store.create({ item: moon, active: true, by: "a@b.c", at: 1_000 }));
    const saved = await Effect.runPromise(
      store.update({
        item: { ...moon, price: 220 },
        active: false,
        expectedVersion: 1,
        by: "d@e.f",
        at: 2_000,
      }),
    );
    expect(saved).toMatchObject({ version: 2, active: false, updatedBy: "d@e.f" });
    const stale = await Effect.runPromise(
      Effect.flip(
        store.update({ item: moon, active: true, expectedVersion: 1, by: "x@y.z", at: 3_000 }),
      ),
    );
    expect(stale).toMatchObject({ _tag: "ShopItemConflict", current: 2 });
    const history = await Effect.runPromise(store.history(10));
    expect(history.map((change) => [change.action, change.by])).toEqual([
      ["deactivate", "d@e.f"],
      ["create", "a@b.c"],
    ]);
    // An inactive item is not served, and stays in the admin's list.
    expect((await Effect.runPromise(store.active)).some((item) => item.id === "paper-moon")).toBe(
      false,
    );
    expect(
      (await Effect.runPromise(store.all)).some((entry) => entry.item.id === "paper-moon"),
    ).toBe(true);
  });

  it("answers an unknown item with not found", async () => {
    const store = await storeOn(env.DB);
    const error = await Effect.runPromise(
      Effect.flip(store.update({ item: moon, active: true, expectedVersion: 1, by: "a", at: 1 })),
    );
    expect(error._tag).toBe("ShopItemNotFound");
  });

  it("reorders the listed items first and logs it once", async () => {
    const store = await storeOn(env.DB);
    const after = await Effect.runPromise(store.reorder(["lantern", "armchair"], "a@b.c", 5));
    expect(after.slice(0, 2).map((entry) => [entry.item.id, entry.item.sortOrder])).toEqual([
      ["lantern", 10],
      ["armchair", 20],
    ]);
    expect((await Effect.runPromise(store.history(5))).map((change) => change.action)).toEqual([
      "reorder",
    ]);
  });
});
