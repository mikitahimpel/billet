import { characterCount } from "@billet/contracts-domain/note";
import type {
  LocalizedText,
  OnboardingAnswer,
  OnboardingStep,
  OnboardingStepId,
} from "@billet/contracts-domain/onboarding";

/**
 * A pick from a set the app owns, such as the cat's coat: any catalogue id is a valid option, so a
 * coat added in an app release needs no server change. Only the app's own steps are open.
 */
export interface OpenChoiceStep {
  readonly _tag: "OpenChoice";
  readonly id: OnboardingStepId;
  readonly title: LocalizedText;
  readonly skippable: boolean;
}

/** Options the app stops on and never sends: an older build that shows them is refused. */
export const refusedOptions: ReadonlySet<string> = new Set(["age-under-13"]);

/** A step an answer is checked against: a served question, or one the app draws itself. */
export type CheckedStep = OnboardingStep | OpenChoiceStep;

/**
 * Why `answer` doesn't fit `step`, or undefined when it does. The schema already checked the shape;
 * this checks it against the catalogue: the kind, the options, the range and the length.
 */
export const answerProblem = (step: CheckedStep, answer: OnboardingAnswer): string | undefined => {
  const mismatch = `step takes a ${step._tag === "OpenChoice" ? "Single" : step._tag} answer`;
  switch (answer._tag) {
    case "Skipped":
      return step.skippable ? undefined : "step can't be skipped";
    case "Single":
      if (refusedOptions.has(answer.option)) return "never stored";
      if (step._tag === "OpenChoice") return undefined;
      if (step._tag !== "Single") return mismatch;
      return step.options.some((option) => option.id === answer.option)
        ? undefined
        : "unknown option";
    case "Multi": {
      if (step._tag !== "Multi") return mismatch;
      const picked = step.options.filter((option) => answer.options.includes(option.id));
      if (picked.length !== answer.options.length) return "unknown option";
      return picked.length > 1 && picked.some((option) => option.exclusive === true)
        ? "an exclusive option goes alone"
        : undefined;
    }
    case "Range":
      if (step._tag !== "Range") return mismatch;
      if (answer.value < step.min || answer.value > step.max) return "out of range";
      return (answer.value - step.min) % step.step === 0 ? undefined : "off the range's steps";
    case "Text":
      if (step._tag !== "Text") return mismatch;
      return characterCount(answer.text) <= step.maxLength ? undefined : "too long";
  }
};
