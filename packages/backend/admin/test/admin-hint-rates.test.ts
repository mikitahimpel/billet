import { describe, expect, it } from "vitest";
import { buildHintRates } from "../src/admin-hint-rates.ts";

const today = "2026-11-07";
const row = (name: string, detail: string, count: number, day = today) => ({
  name,
  detail,
  day,
  count,
  total: 0,
});

describe("buildHintRates", () => {
  it("sets the pairs that saw a hint against the holdout, which reports `<id>-hold`", () => {
    const [shop] = buildHintRates(
      [
        row("TipShown", "shop", 100),
        row("TipAction", "shop", 40),
        row("TipDismissed", "shop", 30),
        row("TipShown", "shop-hold", 10),
        row("TipAction", "shop-hold", 2),
      ],
      today,
    );
    expect(shop?.hint).toBe("shop");
    expect(shop?.show).toMatchObject({ shown: 100, acted: 40, dismissed: 30, actedRate: 0.4 });
    expect(shop?.hold).toMatchObject({ shown: 10, acted: 2, actedRate: 0.2 });
    expect(shop?.lift).toBeCloseTo(0.2);
  });

  it("gives no rate for an arm with too few hints", () => {
    const [pet] = buildHintRates([row("TipShown", "pet", 4), row("TipAction", "pet", 4)], today);
    expect(pet?.show.actedRate).toBeNull();
    expect(pet?.lift).toBeNull();
  });

  it("leaves out days outside the range and other events", () => {
    expect(
      buildHintRates(
        [row("TipShown", "pet", 50, "2026-09-01"), row("CatPetted", "pet", 9)],
        today,
        30,
      ),
    ).toEqual([]);
  });
});
