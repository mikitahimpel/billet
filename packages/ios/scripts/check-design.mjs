// Fails when feature code gains a raw `Color(red:` or `.font(.system(size:` outside the design package: colours
// and type come from `Ink` and the `.nooki*` fonts (docs/design-system.md). Run from anywhere in the repository.
//
// Files that already had raw values when the guard was added are listed in design-baseline.json with their
// counts, and may only shrink. `node check-design.mjs --update` rewrites the list after a cleanup.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");
const baselinePath = join(here, "design-baseline.json");

const roots = ["apps/ios", "packages/ios"];
const skipped = ["packages/ios/design/", "/.build/", "/Tests/", "Tests/", "Billet.xcodeproj/", "/node_modules/"];
const raw = /Color\(\s*red:|\.font\(\s*\.system\(\s*size:/g;

function swiftFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    const rel = relative(root, path) + (entry.isDirectory() ? "/" : "");
    if (skipped.some((part) => rel.includes(part))) return [];
    if (entry.isDirectory()) return swiftFiles(path);
    return entry.name.endsWith(".swift") ? [path] : [];
  });
}

function stripComments(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, (match) => match.replace(/[^\n]/g, " "))
    .replace(/\/\/.*$/gm, "");
}

const counts = {};
for (const base of roots) {
  for (const file of swiftFiles(join(root, base))) {
    const found = stripComments(readFileSync(file, "utf8")).match(raw)?.length ?? 0;
    if (found > 0) counts[relative(root, file)] = found;
  }
}

if (process.argv.includes("--update")) {
  const sorted = Object.fromEntries(Object.entries(counts).sort(([a], [b]) => a.localeCompare(b)));
  writeFileSync(baselinePath, JSON.stringify(sorted, null, 2) + "\n");
  console.log(`design baseline: ${Object.keys(sorted).length} files`);
  process.exit(0);
}

const baseline = JSON.parse(readFileSync(baselinePath, "utf8"));
const violations = Object.entries(counts).flatMap(([file, count]) => {
  const allowed = baseline[file] ?? 0;
  return count > allowed
    ? [`${file}: ${count} raw Color(red:) / .font(.system(size:), ${allowed} allowed`]
    : [];
});

if (violations.length > 0) {
  console.error(violations.join("\n"));
  console.error(
    "Use Ink colours and the .nooki* text styles from the design package (docs/design-system.md).",
  );
  process.exit(1);
}
