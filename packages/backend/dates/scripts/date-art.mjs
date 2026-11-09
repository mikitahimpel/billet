// Gives date ideas their pictures: `pnpm --filter @billet/backend-dates catalog:art <id> <image>`.
// Each image becomes a content-hashed 800x993 WebP in apps/api/public/art/dates, cached for good.
// Needs ImageMagick (`magick`) with WebP.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

const catalogFile = new URL("../src/date-catalog.json", import.meta.url);
const artDir = new URL("../../../../apps/api/public/art/dates/", import.meta.url);

const args = process.argv.slice(2);
if (args.length === 0 || args.length % 2 !== 0) {
  console.error("usage: date-art.mjs <id> <image> [<id> <image>...]");
  process.exit(1);
}

const catalog = JSON.parse(readFileSync(catalogFile, "utf8"));
for (let i = 0; i < args.length; i += 2) {
  const id = Number(args[i]);
  const source = args[i + 1];
  const idea = catalog.ideas.find((it) => it.id === id);
  if (idea === undefined) throw new Error(`no idea ${id} in the catalog`);

  const webp = execFileSync("magick", [
    source,
    "-resize",
    "800x993^",
    "-gravity",
    "center",
    "-extent",
    "800x993",
    "-strip",
    "-quality",
    "78",
    "-define",
    "webp:method=6",
    "webp:-",
  ]);
  // The average colour, shown while the picture loads.
  const color = execFileSync("magick", [
    source,
    "-resize",
    "1x1!",
    "-format",
    "#%[hex:p{0,0}]",
    "info:",
  ])
    .toString()
    .trim()
    .slice(0, 7);
  const name = `${id}-${createHash("sha256").update(webp).digest("hex").slice(0, 8)}.webp`;

  for (const old of readdirSync(artDir)) {
    if (old.startsWith(`${id}-`) && old !== name) rmSync(new URL(old, artDir));
  }
  writeFileSync(new URL(name, artDir), webp);
  idea.art = { path: `/art/dates/${name}`, color };
  console.log(`${id} ${name} ${color} ${(webp.length / 1024).toFixed(0)} KB`);
}
writeFileSync(catalogFile, `${JSON.stringify(catalog, null, 2)}\n`);
execFileSync("node", [new URL("./date-catalog-version.mjs", import.meta.url).pathname], {
  stdio: "inherit",
});
