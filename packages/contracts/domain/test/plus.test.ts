import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { coinPacks } from "@billet/contracts-domain/coin-packs";
import { inks } from "@billet/contracts-domain/inks";
import {
  fitsParcel,
  ParcelId,
  ParcelOffer,
  parcelChoices,
  parcelPriceCeiling,
  plusProductOf,
  plusProducts,
} from "@billet/contracts-domain/plus";
import { postage } from "@billet/contracts-domain/postage";
import { roomItems, starterItems } from "@billet/contracts-domain/shop";

const item = (id: string) => Schema.decodeUnknownSync(ParcelOffer)({ _tag: "Item", item: id });

describe("Ourio Plus", () => {
  it("sells a month and a year, neither a coin pack", () => {
    expect(plusProducts.map(({ plan }) => plan)).toEqual(["monthly", "yearly"]);
    expect(plusProducts.map(({ parcels }) => parcels)).toEqual([1, 12]);
    const packIds: ReadonlyArray<string> = coinPacks.map(({ id }) => id);
    for (const { id } of plusProducts) {
      expect(packIds).not.toContain(id);
      expect(plusProductOf(id)?.id).toBe(id);
    }
    expect(plusProductOf("com.ourio.app.coins.100")).toBeUndefined();
  });

  it("keeps the dearest pieces out of parcels: the ceiling is 320 coins", () => {
    expect(parcelPriceCeiling).toBe(320);
    expect(fitsParcel(item("armchair"))).toBe(true);
    expect(fitsParcel(item("donutbed"))).toBe(false);
    expect(fitsParcel(item("tower"))).toBe(false);
    const dearest = roomItems.toSorted((a, b) => b.price - a.price).slice(0, 2);
    for (const piece of dearest) expect(fitsParcel(item(piece.id)), piece.id).toBe(false);
  });

  it("offers every sold piece, ink, stamp and seal under the ceiling, and nothing free", () => {
    const sold = [
      ...roomItems.filter(
        ({ id, price }) => !starterItems.includes(id) && price <= parcelPriceCeiling,
      ),
      ...inks.filter(({ price }) => price > 0 && price <= parcelPriceCeiling),
      ...postage.filter(({ price }) => price <= parcelPriceCeiling),
    ];
    expect(parcelChoices.length).toBe(sold.length);
    expect(parcelChoices).not.toContainEqual(item("lamp"));
    expect(parcelChoices).not.toContainEqual({ _tag: "Ink", ink: "ink-graphite" });
  });

  it("names a parcel after its transaction, and a year's by its month", () => {
    const decode = Schema.decodeUnknownSync(ParcelId);
    for (const good of ["parcel:2000000900000001", "parcel:mock-ab-12:12", "parcel:x:1"]) {
      expect(decode(good)).toBe(good);
    }
    for (const bad of ["parcel:", "parcel:x:13", "parcel:x:0", "gift:x", "parcel:a b"]) {
      expect(() => decode(bad), bad).toThrow();
    }
  });
});
