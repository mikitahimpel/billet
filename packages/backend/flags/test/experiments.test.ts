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
  it("fills in an experiment kind, a running status and open targeting when left out", () => {
    expect(defineExperiment(spec)).toMatchObject({
      kind: "experiment",
      description: "",
      status: "running",
      targeting: {},
    });
  });

  it("allows a zero weight beside a positive one", () => {
    expect(defineExperiment({ ...spec, variants: { a: 0, b: 1 } }).variants[0]?.weight).toBe(0);
  });

  it("keeps the variants in the order given", () => {
    expect(
      defineExperiment({ ...spec, variants: { b: 2, a: 1, c: 3 } }).variants.map((v) => v.id),
    ).toEqual(["b", "a", "c"]);
  });

  it.each([
    ["one variant", { variants: { a: 1 } }],
    ["a default that is not a variant", { default: "z" }],
    ["only zero weights", { variants: { a: 0, b: 0 } }],
    ["a negative weight", { variants: { a: -1, b: 1 } }],
    ["a description over 500 characters", { description: "x".repeat(501) }],
    ["a malformed app version bound", { targeting: { minAppVersion: "v1" } }],
    ["an unknown age band", { targeting: JSON.parse('{ "ageBands": ["21+"] }') }],
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

  it("ships every entry as a draft, so nothing changes for anyone until the owner starts it", () => {
    for (const experiment of registry) {
      expect([experiment.key, experiment.status, experiment.killed]).toEqual([
        experiment.key,
        "draft",
        false,
      ]);
    }
  });

  it("describes every entry", () => {
    for (const experiment of registry) expect(experiment.description).not.toBe("");
  });

  it("gives every remote flag all its weight on its default, so starting one changes nothing yet", () => {
    for (const experiment of registry.filter(({ kind }) => kind === "flag")) {
      for (const { id, weight } of experiment.variants) {
        expect([id, weight > 0]).toEqual([id, id === experiment.default]);
      }
    }
  });
});
