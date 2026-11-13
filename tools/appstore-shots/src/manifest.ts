import { readFileSync } from "node:fs";

export interface Chip {
  text: string;
  emoji: string;
  /** Left and top of the chip, in percent of the panel. */
  x: number;
  y: number;
  rotate?: number;
}

export interface Panel {
  id: string;
  /** File name stem of the raw screenshot in the raw folder. */
  raw: string;
  bg: "light" | "dark";
  tag: string;
  /** The accent word or words are wrapped in braces: "A tiny home just for {us two}". */
  headline: string;
  chips: Chip[];
}

export interface Manifest {
  locale: string;
  panels: Panel[];
}

export const loadManifest = (file: string): Manifest => JSON.parse(readFileSync(file, "utf8"));

const ACCENT = /\{([^{}]+)\}/;

/** Problems that make a manifest unusable; empty when it is fine. */
export const manifestProblems = (
  manifest: Manifest,
  rawHas: (stem: string) => boolean,
): string[] => {
  const problems: string[] = [];
  const ids = new Set<string>();
  for (const panel of manifest.panels) {
    if (ids.has(panel.id)) problems.push(`${panel.id}: duplicate id`);
    ids.add(panel.id);
    if (!ACCENT.test(panel.headline)) problems.push(`${panel.id}: headline has no {accent} word`);
    if (panel.chips.length < 1 || panel.chips.length > 3)
      problems.push(`${panel.id}: needs 1 to 3 chips`);
    if (!rawHas(panel.raw))
      problems.push(`${panel.id}: raw screenshot ${panel.raw}.png is missing`);
    for (const chip of panel.chips) {
      if (chip.x < -10 || chip.x > 100 || chip.y < 0 || chip.y > 100) {
        problems.push(`${panel.id}: chip "${chip.text}" is off the panel`);
      }
    }
  }
  return problems;
};

export const escapeHtml = (text: string): string =>
  text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** The headline as HTML, its accent in a span. */
export const headlineHtml = (headline: string): string =>
  headline
    .split(/(\{[^{}]+\})/)
    .map((part) =>
      part.startsWith("{")
        ? `<span class="accent">${escapeHtml(part.slice(1, -1))}</span>`
        : escapeHtml(part),
    )
    .join("");
