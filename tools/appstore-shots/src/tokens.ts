/** Mirrors of `packages/ios/design/Sources/Design/Tokens/Palette.swift`; `check-tokens.ts` fails when one drifts. */
export type TokenSource =
  | { kind: "dusk-dark"; name: string }
  | { kind: "classic-light"; name: string }
  | { kind: "classic-dark"; name: string }
  | { kind: "backdrop"; look: "classic" | "dusk"; index: number };

export interface Token {
  hex: string;
  source: TokenSource;
}

export const tokens = {
  lightScreen: { hex: "FBF3E8", source: { kind: "classic-light", name: "screen" } },
  lightWarmTop: { hex: "FFEEDA", source: { kind: "classic-light", name: "warmTop" } },
  lightWarmBottom: { hex: "FFE2C2", source: { kind: "classic-light", name: "warmBottom" } },
  lightWarmGlow: { hex: "FFD9A6", source: { kind: "classic-light", name: "warmGlow" } },
  lightText: { hex: "3A2114", source: { kind: "classic-light", name: "text" } },
  lightTextSecondary: { hex: "6B4A36", source: { kind: "classic-light", name: "textSecondary" } },
  lightAccentText: { hex: "974A18", source: { kind: "classic-light", name: "accentText" } },
  honey: { hex: "F2A65E", source: { kind: "classic-light", name: "honey" } },
  honeyLight: { hex: "FFC27D", source: { kind: "classic-light", name: "honeyLight" } },
  darkScreen: { hex: "110A07", source: { kind: "dusk-dark", name: "screen" } },
  darkSurface: { hex: "24170F", source: { kind: "dusk-dark", name: "surface" } },
  darkWarmTop: { hex: "4A2E18", source: { kind: "dusk-dark", name: "warmTop" } },
  darkWarmBottom: { hex: "32200F", source: { kind: "dusk-dark", name: "warmBottom" } },
  darkWarmGlow: { hex: "6E421C", source: { kind: "dusk-dark", name: "warmGlow" } },
  darkInk: { hex: "F7E7D4", source: { kind: "dusk-dark", name: "ink" } },
  classicBackdrop0: { hex: "F4BF7E", source: { kind: "backdrop", look: "classic", index: 0 } },
  classicBackdrop1: { hex: "B36E3A", source: { kind: "backdrop", look: "classic", index: 1 } },
  duskBackdrop0: { hex: "6B3F1C", source: { kind: "backdrop", look: "dusk", index: 0 } },
  duskBackdrop3: { hex: "0A0605", source: { kind: "backdrop", look: "dusk", index: 3 } },
} satisfies Record<string, Token>;

export type TokenName = keyof typeof tokens;

export const color = (name: TokenName): string => `#${tokens[name].hex}`;
