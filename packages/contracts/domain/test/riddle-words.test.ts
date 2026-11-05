import { describe, expect, it } from "vitest";
import { riddleWords } from "@billet/contracts-domain/riddle-words";

const all = Object.values(riddleWords).flat();
const letters = (word: string) => word.replaceAll(" ", "").length;

describe("riddle words", () => {
  it("are lowercase words of one alphabet, single-spaced", () => {
    for (const { en, ru } of all) {
      expect(en).toMatch(/^[a-z]+( [a-z]+)?$/);
      expect(ru).toMatch(/^[а-яё]+( [а-яё]+)?$/);
    }
  });

  it("leave room for decoys among 12 tiles", () => {
    for (const { en, ru } of all) {
      expect(letters(en), en).toBeLessThanOrEqual(10);
      expect(letters(ru), ru).toBeLessThanOrEqual(10);
    }
  });

  it("never repeat a word in either language", () => {
    for (const language of ["en", "ru"] as const) {
      const seen = all.map((word) => word[language].replaceAll("ё", "е"));
      expect(new Set(seen).size).toBe(seen.length);
    }
  });

  it("offer enough of each tier to keep three choices fresh", () => {
    for (const tier of Object.values(riddleWords)) expect(tier.length).toBeGreaterThanOrEqual(100);
  });
});
