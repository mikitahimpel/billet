import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { defineExperiment, registry } from "../src/experiments.ts";
import { applyConfig, configOf, effectiveExperiments } from "../src/flag-config.ts";

const variant = Schema.decodeSync(VariantId);
const entry = defineExperiment({
  key: "one",
  variants: { a: 1, b: 1 },
  default: "a",
  exposure: 100,
  killed: false,
});

describe("applyConfig", () => {
  it("round-trips a registry entry through its configuration", () => {
    for (const experiment of registry) {
      expect(applyConfig(experiment, configOf(experiment))).toEqual({ experiment });
    }
  });

  it("keeps the registry's variant order whatever order the weights come in", () => {
    const applied = applyConfig(entry, {
      ...configOf(entry),
      weights: { [variant("b")]: 3, [variant("a")]: 1 },
    });
    expect("experiment" in applied && applied.experiment.variants).toEqual([
      { id: "a", weight: 1 },
      { id: "b", weight: 3 },
    ]);
  });

  it.each([
    ["a variant the app lacks", { weights: { a: 1, b: 1, c: 1 } }, "unknown variants: c"],
    ["a variant left out", { weights: { a: 1 } }, "missing variants: b"],
    ["all weights zero", { weights: { a: 0, b: 0 } }, "weight above 0"],
    ["a default outside the variants", { default: "c" }, "not one of its variants"],
  ])("refuses %s", (_, change, message) => {
    const applied = applyConfig(entry, { ...configOf(entry), ...(change as object) });
    expect("error" in applied && applied.error).toContain(message);
  });
});

describe("effectiveExperiments", () => {
  const stored = (config: ReturnType<typeof configOf>, key = "one") => ({
    key: Schema.decodeSync(ExperimentKey)(key),
    config,
    version: 1,
    updatedAt: 1,
    updatedBy: "owner@example.com",
  });

  it("applies a saved row, ignores one for an unknown key, and keeps the registry's order", () => {
    const two = defineExperiment({
      ...configOf(entry),
      key: "two",
      variants: { a: 1, b: 1 },
      killed: false,
      exposure: 100,
      default: "a",
    });
    const result = effectiveExperiments(
      [entry, two],
      [stored({ ...configOf(entry), killed: true }), stored(configOf(entry), "ghost")],
    );
    expect(result.map(({ key, killed }) => [key, killed])).toEqual([
      ["one", true],
      ["two", false],
    ]);
  });

  it("falls back to the registry for a row that no longer fits", () => {
    const result = effectiveExperiments(
      [entry],
      [stored({ ...configOf(entry), weights: { [variant("a")]: 1 } })],
    );
    expect(result).toEqual([entry]);
  });
});
