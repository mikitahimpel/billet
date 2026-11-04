import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { stampPacks } from "@billet/contracts-domain/stamp-packs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "..");

const readJson = (path: string): unknown => JSON.parse(readFileSync(join(root, path), "utf8"));

// The app bundles its own copy of the packs, and Xcode tests purchases from its StoreKit file.
// Both must sell exactly the canonical packs, at the same stamps and prices.
const AppPacks = Schema.Struct({
  packs: Schema.Array(
    Schema.Struct({ id: Schema.String, stamps: Schema.Int, price: Schema.String }),
  ),
});

const StoreKitConfiguration = Schema.Struct({
  products: Schema.Array(
    Schema.Struct({ productID: Schema.String, displayPrice: Schema.String, type: Schema.String }),
  ),
});

const canonical = stampPacks
  .map(({ id, stamps, price }) => ({ id, stamps, price }))
  .toSorted((a, b) => a.id.localeCompare(b.id));

describe("the stamp packs everywhere", () => {
  it("the app's stamp-packs.json sells the canonical packs", () => {
    const { packs } = Schema.decodeUnknownSync(AppPacks)(
      readJson("packages/ios/Sources/Payments/Resources/stamp-packs.json"),
    );
    expect(
      packs
        .map(({ id, stamps, price }) => ({ id, stamps, price }))
        .toSorted((a, b) => a.id.localeCompare(b.id)),
    ).toEqual(canonical);
  });

  it("Billet.storekit sells the canonical packs as consumables", () => {
    const { products } = Schema.decodeUnknownSync(StoreKitConfiguration)(
      // TODO: the new app in apps/ios gets its own .storekit with the Payments wiring.
      readJson("archive/ios-v1/App/Billet.storekit"),
    );
    expect(
      products
        .map(({ productID, displayPrice, type }) => ({ id: productID, price: displayPrice, type }))
        .toSorted((a, b) => a.id.localeCompare(b.id)),
    ).toEqual(canonical.map(({ id, price }) => ({ id, price, type: "Consumable" })));
  });
});
