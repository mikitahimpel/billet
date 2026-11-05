import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { PairId } from "@billet/contracts-domain/pair-id";
import { compareAppVersions, isTargeted } from "../src/targeting.ts";

const pair = Schema.decodeSync(PairId);
const sign = (n: number | undefined) => (n === undefined ? undefined : Math.sign(n));

describe("compareAppVersions", () => {
  it.each([
    ["1.2", "1.2.0", 0],
    ["1.2.0+14", "1.2", 0],
    ["1.10", "1.9", 1],
    ["1.2.0+9", "1.2.0+10", -1],
    ["2", "1.99.99", 1],
    ["1.2.1", "1.2.0+999", 1],
  ])("orders %s against %s", (a, b, expected) => {
    expect(sign(compareAppVersions(a, b))).toBe(expected);
  });

  it.each(["unknown", "", "v1.2", "1.2-beta"])("cannot order %j", (value) => {
    expect(compareAppVersions(value, "1.0")).toBeUndefined();
  });
});

describe("isTargeted", () => {
  const context = { pairId: pair("p1"), appVersion: "1.2.0+14" };

  it("lets everyone in when there are no rules, or only empty lists", () => {
    expect(isTargeted({}, context)).toBe(true);
    expect(isTargeted({ pairIds: [], ageBands: [] }, { ...context, appVersion: "unknown" })).toBe(
      true,
    );
  });

  it("needs every rule to hold", () => {
    expect(isTargeted({ minAppVersion: "1.2", pairIds: [pair("p1")] }, context)).toBe(true);
    expect(isTargeted({ minAppVersion: "1.3", pairIds: [pair("p1")] }, context)).toBe(false);
    expect(isTargeted({ minAppVersion: "1.2", pairIds: [pair("p2")] }, context)).toBe(false);
  });

  it("matches an age band only when the pair's is known and listed", () => {
    expect(isTargeted({ ageBands: ["18+"] }, context)).toBe(false);
    expect(isTargeted({ ageBands: ["18+"] }, { ...context, ageBand: "18+" })).toBe(true);
    expect(isTargeted({ ageBands: ["18+"] }, { ...context, ageBand: "13-17" })).toBe(false);
  });

  it("leaves an unknown build out of either version bound", () => {
    const unknown = { ...context, appVersion: "unknown" };
    expect(isTargeted({ minAppVersion: "0" }, unknown)).toBe(false);
    expect(isTargeted({ maxAppVersion: "99" }, unknown)).toBe(false);
  });

  describe("pairedSince", () => {
    const since = "2026-11-05T09:30Z";
    const at = Date.UTC(2026, 10, 5, 9, 30);

    it("lets in pairs formed at or after the moment", () => {
      expect(isTargeted({ pairedSince: since }, { ...context, pairedAt: at })).toBe(true);
      expect(isTargeted({ pairedSince: since }, { ...context, pairedAt: at + 1 })).toBe(true);
    });

    it("leaves out pairs formed before it, and pairs whose formation time is unknown", () => {
      expect(isTargeted({ pairedSince: since }, { ...context, pairedAt: at - 1 })).toBe(false);
      expect(isTargeted({ pairedSince: since }, context)).toBe(false);
    });

    it("lets every pair in when absent", () => {
      expect(isTargeted({}, { ...context, pairedAt: 0 })).toBe(true);
    });
  });
});
