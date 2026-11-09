import type { OnboardingResponse } from "@billet/contracts-http-api/onboarding";
import type { CheckedStep } from "./answer-check.ts";

/** Never what was typed: a `Text` answer counts as answered, and its words stay in the table. */
export interface OnboardingCountRow {
  readonly stepId: string;
  /** The answer's `_tag`: `Skipped`, `Single`, `Multi`, `Range` or `Text`. */
  readonly kind: string;
  readonly optionIds: ReadonlyArray<string>;
  readonly value: number | null;
}

export interface OnboardingStepStats {
  readonly id: string;
  readonly kind: CheckedStep["_tag"];
  readonly title: string;
  /** One the app draws itself (coat, cat name, invite), not a served question. */
  readonly native: boolean;
  readonly answered: number;
  readonly skipped: number;
  /** `skipped` over everyone who got to the step and did either; null before anyone has. */
  readonly skipRate: number | null;
  /**
   * `Single`/`Multi`: per option in step order, a `Multi` once per pick. `OpenChoice`: most first.
   */
  readonly options: ReadonlyArray<{
    readonly id: string;
    readonly label: string;
    readonly count: number;
  }>;
  /** For `Range`: how many answered each value, lowest first. */
  readonly values: ReadonlyArray<{ readonly value: number; readonly count: number }>;
}

export interface OnboardingStats {
  readonly version: string;
  /** Accounts with at least one stored answer or skip. */
  readonly accounts: number;
  readonly steps: ReadonlyArray<OnboardingStepStats>;
  /** Answers to steps the catalogue no longer has, by step id. */
  readonly retired: ReadonlyArray<{ readonly stepId: string; readonly count: number }>;
}

const optionsOf = (step: CheckedStep, picks: ReadonlyMap<string, number>) => {
  switch (step._tag) {
    case "Single":
    case "Multi":
      return step.options.map((option) => ({
        id: option.id,
        label: option.label.en,
        count: picks.get(option.id) ?? 0,
      }));
    case "OpenChoice":
      return [...picks]
        .toSorted(([a, x], [b, y]) => y - x || (a < b ? -1 : 1))
        .map(([id, count]) => ({ id, label: id, count }));
    case "Range":
    case "Text":
      return [];
  }
};

/** The served steps in order, then the app's own. */
export const buildOnboardingStats = (
  catalogue: OnboardingResponse,
  native: ReadonlyArray<CheckedStep>,
  rows: ReadonlyArray<OnboardingCountRow>,
  accounts: number,
): OnboardingStats => {
  const byStep = Map.groupBy(rows, (row) => row.stepId);
  const served = new Set(catalogue.steps.map((step) => step.id));
  const all: ReadonlyArray<CheckedStep> = [...catalogue.steps, ...native];
  const steps = all.map((step): OnboardingStepStats => {
    const own = byStep.get(step.id) ?? [];
    const skipped = own.filter((row) => row.kind === "Skipped").length;
    const answered = own.length - skipped;
    const picks = new Map<string, number>();
    const values = new Map<number, number>();
    for (const row of own) {
      for (const id of row.optionIds) picks.set(id, (picks.get(id) ?? 0) + 1);
      if (row.kind === "Range" && row.value !== null) {
        values.set(row.value, (values.get(row.value) ?? 0) + 1);
      }
    }
    return {
      id: step.id,
      kind: step._tag,
      title: step.title.en,
      native: !served.has(step.id),
      answered,
      skipped,
      skipRate: own.length === 0 ? null : skipped / own.length,
      options: optionsOf(step, picks),
      values: [...values].toSorted(([a], [b]) => a - b).map(([value, count]) => ({ value, count })),
    };
  });
  const known = new Set<string>(all.map((step) => step.id));
  const retired = [...byStep]
    .filter(([stepId]) => !known.has(stepId))
    .map(([stepId, own]) => ({ stepId, count: own.length }))
    .toSorted((a, b) => (a.stepId < b.stepId ? -1 : 1));
  return { version: catalogue.version, accounts, steps, retired };
};
