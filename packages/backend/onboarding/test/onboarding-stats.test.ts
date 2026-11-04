import { describe, expect, it } from "vitest";
import { nativeSteps, seedCatalogue } from "../src/catalogue.ts";
import { buildOnboardingStats, type OnboardingCountRow } from "../src/onboarding-stats.ts";

const row = (
  stepId: string,
  kind: string,
  optionIds: ReadonlyArray<string> = [],
  value: number | null = null,
): OnboardingCountRow => ({ stepId, kind, optionIds, value });

describe("buildOnboardingStats", () => {
  it("counts answers, skips and picks per step, in the catalogue's order", () => {
    const stats = buildOnboardingStats(
      seedCatalogue,
      nativeSteps,
      [
        row("age", "Single", ["age-18-24"]),
        row("age", "Single", ["age-18-24"]),
        row("age", "Skipped"),
        row("goals", "Multi", ["widgets", "raise-pet"]),
        row("goals", "Multi", ["widgets"]),
        row("name", "Text"),
        row("name", "Skipped"),
        row("cat_coat", "Single", ["grey"]),
        row("cat_coat", "Single", ["ginger"]),
        row("cat_coat", "Single", ["grey"]),
        row("cat_name", "Skipped"),
        row("invite_partner", "Single", ["sent"]),
        row("old-step", "Single", ["x"]),
      ],
      4,
    );
    expect(stats.version).toBe(seedCatalogue.version);
    expect(stats.accounts).toBe(4);
    expect(stats.steps.map((step) => [step.id, step.native])).toEqual([
      ["age", false],
      ["pronouns", false],
      ["name", false],
      ["goals", false],
      ["cat_coat", true],
      ["cat_name", true],
      ["invite_partner", true],
    ]);

    const [age, pronouns, name, goals, coat, catName, invite] = stats.steps;
    expect(age).toMatchObject({ answered: 2, skipped: 1, skipRate: 1 / 3 });
    expect(age?.options.find((option) => option.id === "age-18-24")?.count).toBe(2);
    expect(age?.options.find((option) => option.id === "age-45-plus")?.count).toBe(0);
    expect(pronouns).toMatchObject({ answered: 0, skipped: 0, skipRate: null });
    expect(name).toMatchObject({ answered: 1, skipped: 1, skipRate: 0.5, options: [] });
    expect(goals?.options.find((option) => option.id === "widgets")?.count).toBe(2);
    expect(goals?.options.find((option) => option.id === "raise-pet")?.count).toBe(1);
    expect(coat?.options).toEqual([
      { id: "grey", label: "grey", count: 2 },
      { id: "ginger", label: "ginger", count: 1 },
    ]);
    expect(catName).toMatchObject({ answered: 0, skipped: 1, skipRate: 1 });
    expect(invite?.options).toEqual([{ id: "sent", label: "Sent", count: 1 }]);
    expect(stats.retired).toEqual([{ stepId: "old-step", count: 1 }]);
  });
});
