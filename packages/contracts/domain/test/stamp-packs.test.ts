import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { StampPackId, stampPackOf, stampPacks } from "@billet/contracts-domain/stamp-packs";

describe("stamp packs", () => {
  it("have unique ids and a positive number of stamps", () => {
    expect(new Set(stampPacks.map(({ id }) => id)).size).toBe(stampPacks.length);
    for (const pack of stampPacks) expect(pack.stamps).toBeGreaterThan(0);
  });

  it("finds a pack by product id", () => {
    expect(stampPackOf("com.mikitahimpel.billet.stamps.550")?.stamps).toBe(550);
    expect(stampPackOf("com.mikitahimpel.billet.stamps.5")).toBeUndefined();
  });

  it("decodes only known product ids", () => {
    for (const { id } of stampPacks) expect(Schema.decodeUnknownSync(StampPackId)(id)).toBe(id);
    expect(Schema.decodeUnknownSync(StampPackId)("com.mikitahimpel.billet.stamps.100")).toBe(
      "com.mikitahimpel.billet.stamps.100",
    );
    expect(() => Schema.decodeUnknownSync(StampPackId)("com.other.stamps.100")).toThrow();
  });
});
