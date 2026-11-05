import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { OnboardingAnswer, OnboardingStep } from "@billet/contracts-domain/onboarding";
import { answerProblem } from "../src/answer-check.ts";

const step = Schema.decodeUnknownSync(OnboardingStep);
const answer = Schema.decodeUnknownSync(OnboardingAnswer);
const title = { en: "t", ru: "т" };
const option = (id: string, exclusive?: boolean) => ({
  id,
  label: title,
  ...(exclusive === undefined ? {} : { exclusive }),
});

const single = step({
  _tag: "Single",
  id: "s",
  title,
  skippable: true,
  options: [option("a"), option("b")],
});
const multi = step({
  _tag: "Multi",
  id: "m",
  title,
  skippable: true,
  options: [option("a"), option("b"), option("none", true)],
});
const range = step({ _tag: "Range", id: "r", title, skippable: false, min: 0, max: 10, step: 2 });
const text = step({ _tag: "Text", id: "t", title, skippable: true, maxLength: 5 });

describe("answerProblem", () => {
  it("refuses an under-13 age, which the app never sends", () => {
    const age = step({
      _tag: "Single",
      id: "age",
      title,
      skippable: true,
      options: [option("age-under-13")],
    });
    expect(answerProblem(age, answer({ _tag: "Single", option: "age-under-13" }))).toBeDefined();
  });

  it("takes a skip on a skippable step only", () => {
    expect(answerProblem(single, answer({ _tag: "Skipped" }))).toBeUndefined();
    expect(answerProblem(range, answer({ _tag: "Skipped" }))).toBeDefined();
  });

  it("refuses an answer of another kind", () => {
    expect(answerProblem(single, answer({ _tag: "Multi", options: ["a"] }))).toBeDefined();
    expect(answerProblem(text, answer({ _tag: "Range", value: 1 }))).toBeDefined();
  });

  it("takes a known option, and refuses an unknown one", () => {
    expect(answerProblem(single, answer({ _tag: "Single", option: "b" }))).toBeUndefined();
    expect(answerProblem(single, answer({ _tag: "Single", option: "c" }))).toBeDefined();
    expect(answerProblem(multi, answer({ _tag: "Multi", options: ["a", "b"] }))).toBeUndefined();
    expect(answerProblem(multi, answer({ _tag: "Multi", options: ["a", "z"] }))).toBeDefined();
  });

  it("keeps an exclusive option alone", () => {
    expect(answerProblem(multi, answer({ _tag: "Multi", options: ["none"] }))).toBeUndefined();
    expect(answerProblem(multi, answer({ _tag: "Multi", options: ["a", "none"] }))).toBeDefined();
  });

  it("takes a value in range and on its steps", () => {
    expect(answerProblem(range, answer({ _tag: "Range", value: 0 }))).toBeUndefined();
    expect(answerProblem(range, answer({ _tag: "Range", value: 10 }))).toBeUndefined();
    expect(answerProblem(range, answer({ _tag: "Range", value: 3 }))).toBeDefined();
    expect(answerProblem(range, answer({ _tag: "Range", value: 12 }))).toBeDefined();
    expect(answerProblem(range, answer({ _tag: "Range", value: -2 }))).toBeDefined();
  });

  it("counts a text's characters as a person does", () => {
    expect(answerProblem(text, answer({ _tag: "Text", text: "💛💛💛💛💛" }))).toBeUndefined();
    expect(answerProblem(text, answer({ _tag: "Text", text: "abcdef" }))).toBeDefined();
  });
});
