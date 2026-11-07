import { asc, desc, eq, sql } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import { ShopAsset, ShopCatalogItem } from "@billet/contracts-domain/shop-catalog";
import {
  type AdminShopItem,
  type ShopChange,
  type ShopChangeAction,
  ShopItemConflict,
  ShopItemExists,
  ShopItemNotFound,
  ShopStore,
  ShopStoreUnavailable,
} from "@billet/backend-shop/shop-store";
import { spanMethods } from "@billet/backend-observability/span-methods";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { shopItemChanges, shopItems } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const guarded = <A, E>(effect: Effect.Effect<A, E>) =>
  Effect.mapError(
    effect,
    (cause) => new ShopStoreUnavailable({ reason: "directory-unavailable", cause }),
  );

/** A `shop_items` row as stored: the asset is JSON text. */
export const ShopItemRow = Schema.Struct({
  id: Schema.String,
  kind: Schema.String,
  name: Schema.String,
  blurb: Schema.NullOr(Schema.String),
  mood: Schema.NullOr(Schema.String),
  rarity: Schema.String,
  price: Schema.Int,
  salePrice: Schema.NullOr(Schema.Int),
  saleFrom: Schema.NullOr(Schema.Int),
  saleUntil: Schema.NullOr(Schema.Int),
  dealDiscount: Schema.NullOr(Schema.Number),
  dealOrder: Schema.NullOr(Schema.Int),
  section: Schema.String,
  sortOrder: Schema.Int,
  plus: Schema.Int,
  isNew: Schema.Int,
  asset: Schema.fromJsonString(ShopAsset),
  minBuild: Schema.NullOr(Schema.Int),
  active: Schema.Int,
  version: Schema.Int,
  createdAt: Schema.Int,
  createdBy: Schema.String,
  updatedAt: Schema.Int,
  updatedBy: Schema.String,
});
type Row = typeof ShopItemRow.Type;

/** A `shop_item_changes` row as stored. */
export const ShopChangeRow = Schema.Struct({
  id: Schema.Int,
  itemId: Schema.String,
  at: Schema.Int,
  by: Schema.String,
  action: Schema.String,
  before: Schema.NullOr(Schema.String),
  after: Schema.NullOr(Schema.String),
});

const decodeRows = Schema.decodeUnknownEffect(Schema.Array(ShopItemRow));
const decodeChanges = Schema.decodeUnknownEffect(Schema.Array(ShopChangeRow));
const decodeItem = Schema.decodeUnknownOption(ShopCatalogItem);

/** The catalog entry of a stored row; a row that no longer decodes (a retired kind) is none. */
const itemOfRow = (row: Row) =>
  decodeItem({
    id: row.id,
    kind: row.kind,
    name: row.name,
    ...(row.blurb === null ? {} : { blurb: row.blurb }),
    ...(row.mood === null ? {} : { mood: row.mood }),
    rarity: row.rarity,
    price: row.price,
    ...(row.salePrice === null || row.saleFrom === null || row.saleUntil === null
      ? {}
      : { sale: { price: row.salePrice, from: row.saleFrom, until: row.saleUntil } }),
    ...(row.dealDiscount === null || row.dealOrder === null
      ? {}
      : { deal: { discount: row.dealDiscount, order: row.dealOrder } }),
    section: row.section,
    sortOrder: row.sortOrder,
    ...(row.plus === 1 ? { plus: true } : {}),
    ...(row.isNew === 1 ? { isNew: true } : {}),
    asset: row.asset,
    ...(row.minBuild === null ? {} : { minBuild: row.minBuild }),
  });

const adminOf = (row: Row): AdminShopItem[] =>
  Option.toArray(itemOfRow(row)).map((item) => ({
    item,
    active: row.active === 1,
    version: row.version,
    createdAt: row.createdAt,
    createdBy: row.createdBy,
    updatedAt: row.updatedAt,
    updatedBy: row.updatedBy,
  }));

/** The row's columns for a catalog entry. */
const columnsOf = (item: ShopCatalogItem) => ({
  kind: item.kind,
  name: item.name,
  blurb: item.blurb ?? null,
  mood: item.mood ?? null,
  rarity: item.rarity,
  price: item.price,
  salePrice: item.sale?.price ?? null,
  saleFrom: item.sale?.from ?? null,
  saleUntil: item.sale?.until ?? null,
  dealDiscount: item.deal?.discount ?? null,
  dealOrder: item.deal?.order ?? null,
  section: item.section,
  sortOrder: item.sortOrder,
  plus: item.plus === true ? 1 : 0,
  isNew: item.isNew === true ? 1 : 0,
  asset: JSON.stringify(item.asset),
  minBuild: item.minBuild ?? null,
});

/** A raw statement for `atomically`, for the one that Drizzle's builder cannot express. */
const statement = (query: string, params: ReadonlyArray<unknown>) => ({
  toSQL: () => ({ sql: query, params }),
});

const snapshot = (admin: AdminShopItem) => ({ ...admin.item, active: admin.active });

const makeStore = (db: DirectoryDatabase): ShopStore["Service"] => {
  const rows = guarded(
    db.select().from(shopItems).orderBy(asc(shopItems.sortOrder), asc(shopItems.id)),
  ).pipe(Effect.flatMap((found) => guarded(decodeRows(found))));

  const all = Effect.map(rows, (found) => found.flatMap(adminOf));

  const one = (id: string) =>
    guarded(db.select().from(shopItems).where(eq(shopItems.id, id))).pipe(
      Effect.flatMap((found) => guarded(decodeRows(found))),
      Effect.map((found) => found.flatMap(adminOf)[0]),
    );

  const log = (
    itemId: string,
    action: ShopChangeAction,
    by: string,
    at: number,
    before: unknown,
    after: unknown,
  ) =>
    db.insert(shopItemChanges).values({
      itemId,
      at,
      by,
      action,
      before: before === undefined ? null : JSON.stringify(before),
      after: after === undefined ? null : JSON.stringify(after),
    });

  return ShopStore.of(
    spanMethods("ShopStore", {
      active: Effect.map(all, (items) =>
        items.filter((entry) => entry.active).map((entry) => entry.item),
      ),
      all,
      create: ({ item, active, by, at }) =>
        Effect.gen(function* () {
          if ((yield* one(item.id)) !== undefined) {
            return yield* Effect.fail(new ShopItemExists({ id: item.id }));
          }
          const made: AdminShopItem = {
            item,
            active,
            version: 1,
            createdAt: at,
            createdBy: by,
            updatedAt: at,
            updatedBy: by,
          };
          yield* guarded(
            atomically(db, [
              db.insert(shopItems).values({
                id: item.id,
                ...columnsOf(item),
                active: active ? 1 : 0,
                version: 1,
                createdAt: at,
                createdBy: by,
                updatedAt: at,
                updatedBy: by,
              }),
              log(item.id, "create", by, at, undefined, snapshot(made)),
            ]),
          );
          return made;
        }),
      update: ({ item, active, by, at, expectedVersion }) =>
        Effect.gen(function* () {
          const before = yield* one(item.id);
          if (before === undefined)
            return yield* Effect.fail(new ShopItemNotFound({ id: item.id }));
          if (before.version !== expectedVersion) {
            return yield* Effect.fail(
              new ShopItemConflict({ id: item.id, current: before.version }),
            );
          }
          const action: ShopChangeAction =
            before.active !== active ? (active ? "activate" : "deactivate") : "edit";
          const after: AdminShopItem = {
            ...before,
            item,
            active,
            version: before.version + 1,
            updatedAt: at,
            updatedBy: by,
          };
          // The version in the WHERE keeps a second editor from overwriting this save unseen, and
          // the log line is written only if this save is the one that landed.
          yield* guarded(
            atomically(db, [
              db
                .update(shopItems)
                .set({
                  ...columnsOf(item),
                  active: active ? 1 : 0,
                  version: after.version,
                  updatedAt: at,
                  updatedBy: by,
                })
                .where(
                  sql`${shopItems.id} = ${item.id} AND ${shopItems.version} = ${expectedVersion}`,
                ),
              statement(
                `INSERT INTO shop_item_changes (item_id, at, by, action, before, after)
                   SELECT ?, ?, ?, ?, ?, ? WHERE EXISTS (
                     SELECT 1 FROM shop_items
                     WHERE id = ? AND version = ? AND updated_at = ? AND updated_by = ?)`,
                [
                  item.id,
                  at,
                  by,
                  action,
                  JSON.stringify(snapshot(before)),
                  JSON.stringify(snapshot(after)),
                  item.id,
                  after.version,
                  at,
                  by,
                ],
              ),
            ]),
          );
          const now = yield* one(item.id);
          if (now === undefined || now.version !== after.version || now.updatedBy !== by) {
            return yield* Effect.fail(
              new ShopItemConflict({ id: item.id, current: now?.version ?? 0 }),
            );
          }
          return after;
        }),
      reorder: (ids, by, at) =>
        Effect.gen(function* () {
          const before = yield* all;
          const known = new Set(before.map((entry) => entry.item.id));
          const listed = ids.filter((id, index) => known.has(id) && ids.indexOf(id) === index);
          if (listed.length === 0) return before;
          yield* guarded(
            atomically(db, [
              ...listed.map((id, index) =>
                db
                  .update(shopItems)
                  .set({ sortOrder: (index + 1) * 10, updatedAt: at, updatedBy: by })
                  .where(eq(shopItems.id, id)),
              ),
              log(
                "*",
                "reorder",
                by,
                at,
                before.filter((entry) => listed.includes(entry.item.id)).map((e) => e.item.id),
                listed,
              ),
            ]),
          );
          return yield* all;
        }),
      history: (limit) =>
        guarded(
          db.select().from(shopItemChanges).orderBy(desc(shopItemChanges.id)).limit(limit),
        ).pipe(
          Effect.flatMap((found) => guarded(decodeChanges(found))),
          Effect.map((found) =>
            found.map((row): ShopChange => ({
              id: row.id,
              itemId: row.itemId,
              at: row.at,
              by: row.by,
              action: row.action as ShopChangeAction,
              before: row.before === null ? null : JSON.parse(row.before),
              after: row.after === null ? null : JSON.parse(row.after),
            })),
          ),
        ),
    }),
  );
};

/** `ShopStore` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const ShopStoreLive = (binding: D1Database): Layer.Layer<ShopStore> =>
  Layer.effect(ShopStore, Effect.map(openDirectoryDatabase(binding), makeStore));
