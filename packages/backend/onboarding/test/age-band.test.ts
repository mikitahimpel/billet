import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { declaresMinor } from "../src/age-band.ts";
import { StoredOnboardingAnswer } from "../src/onboarding-repository.ts";

const answer = (stepId: string, value: unknown) =>
  Schema.decodeUnknownSync(StoredOnboardingAnswer)({
    userId: "u",
    stepId,
    version: "2026-11-04",
    answer: value,
    answeredAt: 1,
  });

describe("declaresMinor", () => {
  it("is true only for the age step answered 13 to 17", () => {
    expect(declaresMinor([answer("age", { _tag: "Single", option: "age-13-17" })])).toBe(true);
    expect(declaresMinor([answer("age", { _tag: "Single", option: "age-18-24" })])).toBe(false);
    expect(declaresMinor([answer("age", { _tag: "Skipped" })])).toBe(false);
    expect(declaresMinor([answer("goals", { _tag: "Single", option: "age-13-17" })])).toBe(false);
    expect(declaresMinor([])).toBe(false);
  });
});
