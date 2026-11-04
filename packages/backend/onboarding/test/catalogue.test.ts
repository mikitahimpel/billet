import { describe, expect, it } from "vitest";
import { seedCatalogue } from "../src/catalogue.ts";

describe("the seeded catalogue", () => {
  it("has distinct step ids, and distinct option ids within each step", () => {
    const ids = seedCatalogue.steps.map((step) => step.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const step of seedCatalogue.steps) {
      if (step._tag !== "Single" && step._tag !== "Multi") continue;
      const options = step.options.map((option) => option.id);
      expect(new Set(options).size, step.id).toBe(options.length);
    }
  });

  it("lets every step be skipped", () => {
    expect(seedCatalogue.steps.every((step) => step.skippable)).toBe(true);
  });

  it("asks for an age as buckets, never a date", () => {
    const age = seedCatalogue.steps.find((step) => step.id === "age");
    expect(age?._tag).toBe("Single");
    if (age?._tag === "Single") {
      expect(age.options.map((option) => option.id)).toEqual([
        "age-13-17",
        "age-18-24",
        "age-25-34",
        "age-35-44",
        "age-45-plus",
      ]);
    }
  });

  it("follows the design's order", () => {
    expect(seedCatalogue.steps.map((step) => step.id)).toEqual([
      "age",
      "pronouns",
      "name",
      "goals",
    ]);
  });
});
