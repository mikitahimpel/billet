import { Context, Data, type Effect } from "effect";
import type { ShopCatalogItem } from "@billet/contracts-domain/shop-catalog";

/** An item as the admin sees it: the catalog entry plus its state and who last touched it. */
export interface AdminShopItem {
  readonly item: ShopCatalogItem;
  readonly active: boolean;
  /** Goes up by one per save, so two editors cannot overwrite each other. */
  readonly version: number;
  readonly createdAt: number;
  readonly createdBy: string;
  readonly updatedAt: number;
  readonly updatedBy: string;
}

export type ShopChangeAction = "create" | "edit" | "activate" | "deactivate" | "reorder";

/** One line of the audit log: who, when, what, and the item before and after. */
export interface ShopChange {
  readonly id: number;
  readonly itemId: string;
  readonly at: number;
  readonly by: string;
  readonly action: ShopChangeAction;
  readonly before: unknown;
  readonly after: unknown;
}

/** The store could not be read or written. `reason` is a fixed label. */
export class ShopStoreUnavailable extends Data.TaggedError("ShopStoreUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}

/** A create under an id that is taken: ids are never reused. */
export class ShopItemExists extends Data.TaggedError("ShopItemExists")<{ readonly id: string }> {}

export class ShopItemNotFound extends Data.TaggedError("ShopItemNotFound")<{
  readonly id: string;
}> {}

/** A save made against a version that is no longer the current one. */
export class ShopItemConflict extends Data.TaggedError("ShopItemConflict")<{
  readonly id: string;
  readonly current: number;
}> {}

/** What the admin sets on an item; its id never changes. */
export interface ShopItemSave {
  readonly item: ShopCatalogItem;
  readonly active: boolean;
  readonly by: string;
  readonly at: number;
}

/**
 * The shop's catalog in D1. Items are never deleted: an id stays once it has been sold, and an
 * inactive item stays owned by every pair that bought it.
 */
export class ShopStore extends Context.Service<
  ShopStore,
  {
    /** The active items, in shelf order. */
    readonly active: Effect.Effect<ReadonlyArray<ShopCatalogItem>, ShopStoreUnavailable>;
    /** Every item, in shelf order, with its state. */
    readonly all: Effect.Effect<ReadonlyArray<AdminShopItem>, ShopStoreUnavailable>;
    readonly create: (
      save: ShopItemSave,
    ) => Effect.Effect<AdminShopItem, ShopStoreUnavailable | ShopItemExists>;
    readonly update: (
      save: ShopItemSave & { readonly expectedVersion: number },
    ) => Effect.Effect<AdminShopItem, ShopStoreUnavailable | ShopItemNotFound | ShopItemConflict>;
    /** Gives the listed items sort orders 10, 20, … in this order; others keep theirs. */
    readonly reorder: (
      ids: ReadonlyArray<string>,
      by: string,
      at: number,
    ) => Effect.Effect<ReadonlyArray<AdminShopItem>, ShopStoreUnavailable>;
    /** The audit log, newest first. */
    readonly history: (
      limit: number,
    ) => Effect.Effect<ReadonlyArray<ShopChange>, ShopStoreUnavailable>;
  }
>()("@billet/backend-shop/ShopStore") {}
