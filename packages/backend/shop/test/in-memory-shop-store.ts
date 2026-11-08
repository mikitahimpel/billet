import { Effect, Layer } from "effect";
import {
  type AdminShopItem,
  type ShopChange,
  ShopItemConflict,
  ShopItemExists,
  ShopItemNotFound,
  ShopStore,
} from "../src/shop-store.ts";
import { seedAt, seedBy, seedItems } from "../src/shop-seed.ts";
import type { ShopCatalogItem } from "@billet/contracts-domain/shop-catalog";

/** A `ShopStore` in memory, starting from the seed, for tests of what sits on top of it. */
export const InMemoryShopStore = (
  start: ReadonlyArray<ShopCatalogItem> = seedItems,
): Layer.Layer<ShopStore> => {
  const rows = new Map<string, AdminShopItem>(
    start.map((item) => [
      item.id,
      {
        item,
        active: true,
        version: 1,
        createdAt: seedAt,
        createdBy: seedBy,
        updatedAt: seedAt,
        updatedBy: seedBy,
      },
    ]),
  );
  const changes: ShopChange[] = [];
  const sorted = () => [...rows.values()].toSorted((a, b) => a.item.sortOrder - b.item.sortOrder);
  const note = (
    itemId: string,
    by: string,
    at: number,
    action: ShopChange["action"],
    before: unknown,
    after: unknown,
  ) => changes.push({ id: changes.length + 1, itemId, at, by, action, before, after });
  return Layer.succeed(
    ShopStore,
    ShopStore.of({
      active: Effect.sync(() =>
        sorted()
          .filter((entry) => entry.active)
          .map((entry) => entry.item),
      ),
      all: Effect.sync(sorted),
      create: ({ item, active, by, at }) =>
        Effect.suspend((): Effect.Effect<AdminShopItem, ShopItemExists> => {
          if (rows.has(item.id)) return Effect.fail(new ShopItemExists({ id: item.id }));
          const made = {
            item,
            active,
            version: 1,
            createdAt: at,
            createdBy: by,
            updatedAt: at,
            updatedBy: by,
          };
          rows.set(item.id, made);
          note(item.id, by, at, "create", undefined, { ...item, active });
          return Effect.succeed(made);
        }),
      update: ({ item, active, by, at, expectedVersion }) =>
        Effect.suspend((): Effect.Effect<AdminShopItem, ShopItemConflict | ShopItemNotFound> => {
          const before = rows.get(item.id);
          if (before === undefined) return Effect.fail(new ShopItemNotFound({ id: item.id }));
          if (before.version !== expectedVersion) {
            return Effect.fail(new ShopItemConflict({ id: item.id, current: before.version }));
          }
          const after = {
            ...before,
            item,
            active,
            version: before.version + 1,
            updatedAt: at,
            updatedBy: by,
          };
          rows.set(item.id, after);
          const action = before.active === active ? "edit" : active ? "activate" : "deactivate";
          note(
            item.id,
            by,
            at,
            action,
            { ...before.item, active: before.active },
            { ...item, active },
          );
          return Effect.succeed(after);
        }),
      reorder: (ids, by, at) =>
        Effect.sync(() => {
          const listed = ids.filter((id, index) => rows.has(id) && ids.indexOf(id) === index);
          listed.forEach((id, index) => {
            const entry = rows.get(id);
            if (entry !== undefined) {
              rows.set(id, {
                ...entry,
                item: { ...entry.item, sortOrder: (index + 1) * 10 },
                updatedAt: at,
                updatedBy: by,
              });
            }
          });
          if (listed.length > 0) note("*", by, at, "reorder", undefined, listed);
          return sorted();
        }),
      history: (limit) => Effect.sync(() => changes.toReversed().slice(0, limit)),
    }),
  );
};
