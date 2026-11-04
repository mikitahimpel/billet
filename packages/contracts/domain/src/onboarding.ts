import { Schema } from "effect";
import { characterCount } from "./note.ts";

/**
 * A stable id from the onboarding catalogue: a step or one of its options. Lowercase letters,
 * digits, hyphens and underscores, starting with a letter, at most 40. Ids never change once
 * shipped, so an answer means the same thing whatever the wording says later.
 */
const catalogueId = Schema.String.check(Schema.isPattern(/^[a-z][a-z0-9_-]{0,39}$/));

export const OnboardingStepId = catalogueId.pipe(Schema.brand("OnboardingStepId"));
export type OnboardingStepId = typeof OnboardingStepId.Type;

export const OnboardingOptionId = catalogueId.pipe(Schema.brand("OnboardingOptionId"));
export type OnboardingOptionId = typeof OnboardingOptionId.Type;

/** Which edition of the questions an answer was given to, such as `2026-11-04`. */
export const OnboardingVersion = Schema.String.check(
  Schema.isPattern(/^[A-Za-z0-9][A-Za-z0-9.-]{0,39}$/),
);
export type OnboardingVersion = typeof OnboardingVersion.Type;

const words = Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(200));

/** Every string a person reads, in each language the app ships. */
export const LocalizedText = Schema.Struct({ en: words, ru: words });
export type LocalizedText = typeof LocalizedText.Type;

export const OnboardingOption = Schema.Struct({
  id: OnboardingOptionId,
  label: LocalizedText,
  emoji: Schema.optionalKey(Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(16))),
  /** Picking it clears the other picks of a `Multi` step, as "Just exploring" does. */
  exclusive: Schema.optionalKey(Schema.Boolean),
});
export type OnboardingOption = typeof OnboardingOption.Type;

/** The most characters a `Text` step may ask for. */
export const onboardingTextMaxCharacters = 200;

const options = Schema.Array(OnboardingOption).check(Schema.isMinLength(1));

const common = {
  id: OnboardingStepId,
  title: LocalizedText,
  subtitle: Schema.optionalKey(LocalizedText),
  /** Whether the step offers a skip. Every step does today; a skip is stored like an answer. */
  skippable: Schema.Boolean,
};

/**
 * One screen of onboarding. `Single` and `Multi` pick from `options`; an age is a `Single` over
 * buckets, never a date. `Range` picks a whole number from `min` to `max` in steps of `step`.
 * `Text` takes up to `maxLength` characters.
 */
export const OnboardingStep = Schema.TaggedUnion({
  Single: { ...common, options },
  Multi: { ...common, options },
  Range: {
    ...common,
    min: Schema.Int,
    max: Schema.Int,
    step: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)),
    unit: Schema.optionalKey(LocalizedText),
  },
  Text: {
    ...common,
    placeholder: Schema.optionalKey(LocalizedText),
    maxLength: Schema.Int.check(
      Schema.isGreaterThanOrEqualTo(1),
      Schema.isLessThanOrEqualTo(onboardingTextMaxCharacters),
    ),
  },
});
export type OnboardingStep = typeof OnboardingStep.Type;

/** A typed answer: 1 to 200 characters as a person counts them, not only whitespace. */
const AnswerText = Schema.String.check(
  Schema.makeFilter(
    (text) =>
      (text.trim().length > 0 &&
        text.length <= 4 * onboardingTextMaxCharacters &&
        characterCount(text) <= onboardingTextMaxCharacters) ||
      `expected 1 to ${onboardingTextMaxCharacters} characters, not only whitespace`,
  ),
);

/**
 * What the person did on a step. `Skipped` is an answer too, so the skip rate can be counted. The
 * step's own rules (which options, the range, the length) are checked against the catalogue.
 */
export const OnboardingAnswer = Schema.TaggedUnion({
  Skipped: {},
  Single: { option: OnboardingOptionId },
  Multi: {
    options: Schema.Array(OnboardingOptionId).check(
      Schema.isMinLength(1),
      Schema.isMaxLength(40),
      Schema.makeFilter((ids) => new Set(ids).size === ids.length || "expected distinct options"),
    ),
  },
  Range: { value: Schema.Int },
  Text: { text: AnswerText },
});
export type OnboardingAnswer = typeof OnboardingAnswer.Type;
