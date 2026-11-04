import { describe, expect, it } from "vitest";
import { share, type VariantReport } from "@billet/backend-metrics/funnel";
import { verdictOf } from "../src/experiment-verdict.ts";

const variant = (id: string, count: number, of: number): VariantReport => ({
  variant: id,
  pairs: of,
  northStar: share(count, of),
  medianToFirstNote: undefined,
});

describe("the experiment verdict", () => {
  it("has no data until two variants have a pair at day 7", () => {
    expect(verdictOf([])).toMatchObject({ kind: "no-data" });
    expect(verdictOf([variant("a", 3, 10), variant("b", 0, 0)])).toMatchObject({
      kind: "no-data",
      text: expect.stringMatching(/^Not enough data yet/),
    });
  });

  it("calls no result while the intervals overlap, and says when the groups are small", () => {
    const small = verdictOf([variant("a", 4, 10), variant("b", 6, 10)]);
    expect(small).toMatchObject({ kind: "overlap", leader: null, small: true });
    expect(small.text).toMatch(/^Not enough data yet/);
    const big = verdictOf([variant("a", 400, 1000), variant("b", 410, 1000)]);
    expect(big).toMatchObject({ kind: "overlap", small: false });
    expect(big.text).toBe("No difference yet: the 95% intervals overlap.");
  });

  it("names a leader only when its interval clears every other", () => {
    const clear = verdictOf([variant("a", 300, 1000), variant("b", 500, 1000)]);
    expect(clear).toMatchObject({ kind: "ahead", leader: "b", small: false });
    expect(clear.text).toBe("b looks better: its 95% interval doesn't overlap the others'.");
    // Clear of one, not of the third.
    expect(
      verdictOf([variant("a", 300, 1000), variant("b", 500, 1000), variant("c", 480, 1000)]),
    ).toMatchObject({ kind: "overlap" });
  });

  it("still flags a clear gap on few pairs as small", () => {
    expect(verdictOf([variant("a", 1, 40), variant("b", 35, 40)])).toMatchObject({
      kind: "ahead",
      leader: "b",
      small: true,
      text: expect.stringContaining("check again before acting"),
    });
  });
});
