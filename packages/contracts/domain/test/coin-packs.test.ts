import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { CoinPackId, coinPackOf, coinPacks } from "@billet/contracts-domain/coin-packs";

describe("coin packs", () => {
  it("have unique ids and a positive number of coins", () => {
    expect(new Set(coinPacks.map(({ id }) => id)).size).toBe(coinPacks.length);
    for (const pack of coinPacks) expect(pack.coins).toBeGreaterThan(0);
  });

  it("finds a pack by product id", () => {
    expect(coinPackOf("com.ourio.app.coins.550")?.coins).toBe(550);
    expect(coinPackOf("com.ourio.app.coins.5")).toBeUndefined();
  });

  it("resolves the first app's product ids to the same packs", () => {
    for (const pack of coinPacks) {
      expect(coinPackOf(pack.id.replace("com.ourio.app", "com.mikitahimpel.billet"))).toBe(pack);
    }
    expect(coinPackOf("com.mikitahimpel.billet.coins.5")).toBeUndefined();
  });

  it("decodes only known product ids", () => {
    for (const { id } of coinPacks) expect(Schema.decodeUnknownSync(CoinPackId)(id)).toBe(id);
    expect(Schema.decodeUnknownSync(CoinPackId)("com.ourio.app.coins.100")).toBe(
      "com.ourio.app.coins.100",
    );
    expect(() => Schema.decodeUnknownSync(CoinPackId)("com.other.coins.100")).toThrow();
  });
});
