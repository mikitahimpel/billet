import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { coinPacks } from "@billet/contracts-domain/coin-packs";
import { plusGroup, plusProducts } from "@billet/contracts-domain/plus";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "..");

const readJson = (path: string): unknown => JSON.parse(readFileSync(join(root, path), "utf8"));

// The app bundles its own copy of the packs, and Xcode tests purchases from its StoreKit file.
// Both must sell exactly the canonical packs, at the same coins and prices.
const AppPacks = Schema.Struct({
  packs: Schema.Array(
    Schema.Struct({ id: Schema.String, coins: Schema.Int, price: Schema.String }),
  ),
});

const StoreKitConfiguration = Schema.Struct({
  products: Schema.Array(
    Schema.Struct({ productID: Schema.String, displayPrice: Schema.String, type: Schema.String }),
  ),
  subscriptionGroups: Schema.Array(
    Schema.Struct({
      name: Schema.String,
      subscriptions: Schema.Array(
        Schema.Struct({
          productID: Schema.String,
          displayPrice: Schema.String,
          type: Schema.String,
          recurringSubscriptionPeriod: Schema.String,
          familyShareable: Schema.Boolean,
          introductoryOffer: Schema.Null,
        }),
      ),
    }),
  ),
});

const canonical = coinPacks
  .map(({ id, coins, price }) => ({ id, coins, price }))
  .toSorted((a, b) => a.id.localeCompare(b.id));

describe("the coin packs everywhere", () => {
  it("the app's coin-packs.json sells the canonical packs", () => {
    const { packs } = Schema.decodeUnknownSync(AppPacks)(
      readJson("packages/ios/payments/Sources/Payments/Resources/coin-packs.json"),
    );
    expect(
      packs
        .map(({ id, coins, price }) => ({ id, coins, price }))
        .toSorted((a, b) => a.id.localeCompare(b.id)),
    ).toEqual(canonical);
  });

  it("Ourio.storekit sells the canonical packs as consumables", () => {
    const { products } = Schema.decodeUnknownSync(StoreKitConfiguration)(
      readJson("apps/ios/Ourio.storekit"),
    );
    expect(
      products
        .map(({ productID, displayPrice, type }) => ({ id: productID, price: displayPrice, type }))
        .toSorted((a, b) => a.id.localeCompare(b.id)),
    ).toEqual(canonical.map(({ id, price }) => ({ id, price, type: "Consumable" })));
  });
});

describe("Ourio Plus everywhere", () => {
  it("Ourio.storekit has one Plus group with both plans, no trial and no Family Sharing", () => {
    const { subscriptionGroups } = Schema.decodeUnknownSync(StoreKitConfiguration)(
      readJson("apps/ios/Ourio.storekit"),
    );
    expect(subscriptionGroups.map(({ name }) => name)).toEqual([plusGroup]);
    const subscriptions = subscriptionGroups.flatMap((group) => group.subscriptions);
    expect(
      subscriptions
        .map(({ productID, displayPrice, type, recurringSubscriptionPeriod, familyShareable }) => ({
          id: productID,
          price: displayPrice,
          type,
          period: recurringSubscriptionPeriod,
          familyShareable,
        }))
        .toSorted((a, b) => a.id.localeCompare(b.id)),
    ).toEqual(
      plusProducts
        .map(({ id, price, plan }) => ({
          id,
          price,
          type: "RecurringSubscription",
          period: plan === "monthly" ? "P1M" : "P1Y",
          familyShareable: false,
        }))
        .toSorted((a, b) => a.id.localeCompare(b.id)),
    );
  });
});
