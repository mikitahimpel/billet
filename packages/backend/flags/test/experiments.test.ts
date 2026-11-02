import { describe, expect, it } from "vitest";
import { defineExperiment, defineExperiments, registry } from "../src/experiments.ts";

const spec = {
  key: "home-direction",
  variants: { a: 1, b: 1 },
  default: "a",
  exposure: 100,
  killed: false,
};

describe("defineExperiment", () => {
  it("keeps the variants in the order given", () => {
    expect(
      defineExperiment({ ...spec, variants: { b: 2, a: 1, c: 3 } }).variants.map((v) => v.id),
    ).toEqual(["b", "a", "c"]);
  });

  it.each([
    ["one variant", { variants: { a: 1 } }],
    ["a default that is not a variant", { default: "z" }],
    ["a zero weight", { variants: { a: 0, b: 1 } }],
    ["a fractional weight", { variants: { a: 0.5, b: 1 } }],
    ["exposure above 100", { exposure: 101 }],
    ["negative exposure", { exposure: -1 }],
    ["fractional exposure", { exposure: 12.5 }],
    ["an upper-case key", { key: "Home" }],
    ["a key with spaces", { key: "home direction" }],
    ["an empty key", { key: "" }],
    ["a key over 40 characters", { key: "a".repeat(41) }],
    ["an upper-case variant", { variants: { A: 1, b: 1 }, default: "b" }],
  ])("refuses %s", (_, change) => {
    expect(() => defineExperiment({ ...spec, ...change })).toThrow();
  });

  it("refuses two experiments with one key", () => {
    expect(() => defineExperiments([spec, spec])).toThrow("share a key");
  });
});

describe("the registry", () => {
  it("is valid, and every experiment in it has a default among its variants", () => {
    for (const experiment of registry) {
      expect(experiment.variants.map((v) => v.id)).toContain(experiment.default);
    }
  });

  it("ships the first planned test switched off", () => {
    const home = registry.find(({ key }) => key === "home-direction");
    expect(home?.killed).toBe(true);
  });
});
