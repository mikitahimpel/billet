import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { renderPage } from "./chrome.ts";
import { tokenDrift } from "./check-tokens.ts";
import { loadManifest, manifestProblems } from "./manifest.ts";
import { flattenToRgb, pngInfo } from "./png.ts";
import { defaultSizeIds, sizes } from "./sizes.ts";
import { contactSheetHtml, contactSheetSize, panelHtml } from "./template.ts";

const here = new URL(".", import.meta.url).pathname;

const { values } = parseArgs({
  options: {
    locale: { type: "string", default: "en" },
    raw: { type: "string", default: join(homedir(), "Developer/billet-shots/appstore/raw") },
    out: { type: "string", default: join(homedir(), "Developer/billet-shots/appstore") },
    sizes: { type: "string", default: defaultSizeIds.join(",") },
    panel: { type: "string", multiple: true },
    check: { type: "boolean", default: false },
  },
});

const wanted = values.sizes!.split(",").map((id) => {
  const size = sizes.find((candidate) => candidate.id === id);
  if (!size) throw new Error(`unknown size ${id}; known: ${sizes.map((s) => s.id).join(", ")}`);
  return size;
});
const manifest = loadManifest(resolve(here, "../manifest", `${values.locale}.json`));
const panels = manifest.panels.filter((p) => !values.panel || values.panel.includes(p.id));
const rawFile = (stem: string): string => join(values.raw!, `${stem}.png`);
const outFile = (sizeId: string, index: number, id: string): string =>
  join(values.out!, manifest.locale, sizeId, `${String(index + 1).padStart(2, "0")}-${id}.png`);

const problems = [
  ...tokenDrift(),
  ...manifestProblems(manifest, (stem) => existsSync(rawFile(stem))),
];

if (values.check) {
  const all = loadManifest(resolve(here, "../manifest", `${values.locale}.json`)).panels;
  all.forEach((panel, index) => {
    for (const size of wanted) {
      const file = outFile(size.id, index, panel.id);
      if (!existsSync(file)) return void problems.push(`${file}: missing`);
      const info = pngInfo(readFileSync(file));
      if (info.width !== size.width || info.height !== size.height) {
        problems.push(
          `${file}: is ${info.width}x${info.height}, wants ${size.width}x${size.height}`,
        );
      }
      if (info.colorType !== 2)
        problems.push(`${file}: colour type ${info.colorType} (alpha channel or palette)`);
    }
  });
  if (problems.length) {
    console.error(problems.join("\n"));
    process.exit(1);
  }
  console.log(
    `ok: ${all.length} panels x ${wanted.length} sizes, tokens in step with Palette.swift`,
  );
  process.exit(0);
}

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}

const work = join(values.out!, ".work");
mkdirSync(work, { recursive: true });
for (const size of wanted) {
  mkdirSync(join(values.out!, manifest.locale, size.id), { recursive: true });
  panels.forEach((panel) => {
    const index = manifest.panels.indexOf(panel);
    const html = join(work, `${size.id}-${panel.id}.html`);
    const shot = join(work, `${size.id}-${panel.id}.png`);
    writeFileSync(
      html,
      panelHtml(panel, pathToFileURL(rawFile(panel.raw)).href, size.width, size.height),
    );
    renderPage(html, shot, size.width, size.height);
    writeFileSync(outFile(size.id, index, panel.id), flattenToRgb(readFileSync(shot)));
    console.log(`${size.id} ${panel.id}`);
  });
}

const sheetSize = wanted[0]!;
const thumb = 360;
const html = join(work, "contact-sheet.html");
const shot = join(work, "contact-sheet.png");
writeFileSync(
  html,
  contactSheetHtml(
    manifest.panels.map(
      (panel, index) => pathToFileURL(outFile(sheetSize.id, index, panel.id)).href,
    ),
    thumb,
  ),
);
const [sheetWidth, sheetHeight] = contactSheetSize(manifest.panels.length, thumb);
renderPage(html, shot, sheetWidth, sheetHeight);
writeFileSync(
  join(values.out!, manifest.locale, "contact-sheet.png"),
  flattenToRgb(readFileSync(shot)),
);
rmSync(work, { recursive: true, force: true });
console.log(`contact sheet ${sheetWidth}x${sheetHeight}`);
