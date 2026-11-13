import { pathToFileURL } from "node:url";
import { fileURLToPath } from "node:url";
import { designWidth } from "./sizes.ts";
import { color } from "./tokens.ts";
import { escapeHtml, headlineHtml, type Panel } from "./manifest.ts";

const font = (relative: string): string =>
  pathToFileURL(fileURLToPath(new URL(relative, import.meta.url))).href;

const fonts = `
@font-face { font-family: "Bricolage"; font-weight: 600; src: url("${font("../../../apps/ios/Nooki/Resources/Fonts/BricolageGrotesque-SemiBold.ttf")}"); }
@font-face { font-family: "Bricolage"; font-weight: 700; src: url("${font("../../../apps/ios/Nooki/Resources/Fonts/BricolageGrotesque-Bold.ttf")}"); }
@font-face { font-family: "Bricolage"; font-weight: 800; src: url("${font("../../../apps/ios/Nooki/Resources/Fonts/BricolageGrotesque-ExtraBold.ttf")}"); }
@font-face { font-family: "Caveat"; font-weight: 600; src: url("${font("../fonts/caveat-semibold.ttf")}"); }`;

const backgrounds = {
  light: {
    bg: `radial-gradient(120% 55% at 50% 100%, ${color("classicBackdrop0")} 0%, transparent 70%), linear-gradient(180deg, ${color("lightWarmTop")} 0%, ${color("lightWarmBottom")} 55%, ${color("lightWarmGlow")} 100%)`,
    text: color("lightText"),
    muted: color("lightTextSecondary"),
    accent: color("lightAccentText"),
  },
  dark: {
    bg: `radial-gradient(110% 50% at 50% 100%, ${color("darkWarmGlow")} 0%, transparent 70%), linear-gradient(180deg, ${color("darkWarmTop")} 0%, ${color("darkWarmBottom")} 50%, ${color("darkScreen")} 100%)`,
    text: color("darkInk"),
    muted: `${color("darkInk")}b3`,
    accent: color("honey"),
  },
};

const chipHtml = (chip: Panel["chips"][number]): string =>
  `<div class="chip" style="left:${chip.x}%;top:${chip.y}%;transform:rotate(${chip.rotate ?? 0}deg)"><span class="emoji">${chip.emoji}</span>${escapeHtml(chip.text)}</div>`;

/** One panel as a page that is `width` x `height` pixels: the layout is drawn at 1320 wide and scaled by width. */
export const panelHtml = (panel: Panel, rawUrl: string, width: number, height: number): string => {
  const scale = width / designWidth;
  const designHeight = Math.round(height / scale);
  const look = backgrounds[panel.bg];
  return `<!doctype html><html><head><meta charset="utf-8"><style>${fonts}
* { box-sizing: border-box; margin: 0; }
html, body { width: ${width}px; height: ${height}px; overflow: hidden; background: ${look.bg}; }
.panel { position: relative; width: ${designWidth}px; height: ${designHeight}px; transform: scale(${scale}); transform-origin: 0 0; overflow: hidden; font-family: "Bricolage", system-ui, sans-serif; color: ${look.text}; text-align: center; }
.tag { position: absolute; top: 118px; width: 100%; font-weight: 600; font-size: 46px; letter-spacing: 0.01em; color: ${look.muted}; }
.headline { position: absolute; top: 196px; width: 100%; padding: 0 70px; font-weight: 800; font-size: 128px; line-height: 1.04; letter-spacing: -0.02em; }
.accent { font-family: "Caveat", cursive; font-weight: 600; font-size: 1.34em; letter-spacing: 0; color: ${look.accent}; display: inline-block; line-height: 0.8; position: relative; transform: rotate(-3deg); }
.accent::after { content: ""; position: absolute; left: 4%; right: 4%; bottom: -0.02em; height: 0.07em; border-radius: 9px; background: ${look.accent}; opacity: 0.85; }
.phone { position: absolute; left: 150px; top: 640px; width: 1020px; padding: 24px; border-radius: 140px; background: linear-gradient(160deg, #2b2623, #0c0a09 40%, #1b1715); box-shadow: 0 0 0 3px #4a413a inset, 0 60px 120px rgba(20, 8, 0, 0.45), 0 20px 40px rgba(20, 8, 0, 0.3); }
.phone img { display: block; width: 100%; border-radius: 118px; }
.island { position: absolute; top: 56px; left: 50%; width: 300px; height: 88px; margin-left: -150px; border-radius: 44px; background: #000; }
.chip { position: absolute; display: flex; align-items: center; gap: 18px; padding: 24px 42px 24px 32px; border-radius: 999px; background: rgba(255, 255, 255, 0.97); color: ${color("lightText")}; font-weight: 700; font-size: 46px; white-space: nowrap; box-shadow: 0 18px 44px rgba(20, 8, 0, 0.3); }
.emoji { font-size: 54px; line-height: 1; }
</style></head><body><div class="panel">
<div class="tag">${escapeHtml(panel.tag)}</div>
<div class="headline">${headlineHtml(panel.headline)}</div>
<div class="phone"><img src="${rawUrl}" alt=""><div class="island"></div></div>
${panel.chips.map(chipHtml).join("\n")}
</div></body></html>`;
};

/** All the finished panels side by side on one dark sheet. */
export const contactSheetHtml = (images: string[], thumbWidth: number): string => {
  const gap = 24;
  const width = images.length * thumbWidth + (images.length + 1) * gap;
  const height = Math.round((thumbWidth * 2868) / 1320) + gap * 2;
  return `<!doctype html><html><head><meta charset="utf-8"><style>
html, body { margin: 0; width: ${width}px; height: ${height}px; background: #1b110b; }
body { display: flex; gap: ${gap}px; padding: ${gap}px; box-sizing: border-box; }
img { width: ${thumbWidth}px; display: block; border-radius: 18px; }
</style></head><body>${images.map((src) => `<img src="${src}" alt="">`).join("")}</body></html>`;
};

export const contactSheetSize = (count: number, thumbWidth: number): [number, number] => [
  count * thumbWidth + (count + 1) * 24,
  Math.round((thumbWidth * 2868) / 1320) + 48,
];
