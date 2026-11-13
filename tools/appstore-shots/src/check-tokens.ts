import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { tokens, type Token } from "./tokens.ts";

export const paletteFile = fileURLToPath(
  new URL("../../../packages/ios/design/Sources/Design/Tokens/Palette.swift", import.meta.url),
);

const HEX = "0x([0-9A-Fa-f]{6})";

const find = (source: string, pattern: RegExp): string | undefined =>
  pattern.exec(source)?.[1]?.toUpperCase();

/** The hex the Swift palette holds for a token, or undefined when its line can't be found. */
export const swiftHex = (palette: string, token: Token): string | undefined => {
  const s = token.source;
  switch (s.kind) {
    case "dusk-dark":
      return s.name === "ink"
        ? find(palette, new RegExp(`let ink: UInt32 = ${HEX}`))
        : find(palette, new RegExp(`tones\\.${s.name}\\.dark = RGBA\\(hex: ${HEX}`));
    case "classic-light":
      return s.name === "honey" || s.name === "honeyLight"
        ? find(palette, new RegExp(`\\b${s.name}: RGBA\\(hex: ${HEX}`))
        : find(palette, new RegExp(`\\b${s.name}: Adaptive\\(\\s*light: RGBA\\(hex: ${HEX}`));
    case "classic-dark":
      return find(
        palette,
        new RegExp(
          `\\b${s.name}: Adaptive\\(\\s*light: RGBA\\([^)]*\\),\\s*dark: RGBA\\(hex: ${HEX}`,
        ),
      );
    case "backdrop": {
      const block =
        s.look === "classic"
          ? /backdrop: \[((?:\s*RGBA\(hex: 0x[0-9A-Fa-f]{6}\),?)+)\]/.exec(palette)?.[1]
          : /tones\.backdrop = \[([^\]]*)\]/.exec(palette)?.[1];
      const hexes = [...(block ?? "").matchAll(/0x([0-9A-Fa-f]{6})/g)].map((m) => m[1]!);
      return hexes[s.index]?.toUpperCase();
    }
  }
};

/** One message per token whose mirror differs from the Swift palette. */
export const tokenDrift = (palette = readFileSync(paletteFile, "utf8")): string[] =>
  Object.entries(tokens).flatMap(([name, token]) => {
    const swift = swiftHex(palette, token);
    return swift === token.hex
      ? []
      : [`${name}: tokens.ts has ${token.hex}, Palette.swift has ${swift ?? "nothing"}`];
  });
