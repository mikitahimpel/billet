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

// Content scrolling under the Home header and the tab bar fades out on every tab: each tab's vertical scroll
// view carries `.softScrollEdges()`, and nothing sets a hard edge. The tabs are the views Home switches on.
const home = join(root, "apps/ios/Nooki/UI/HomeView.swift");
const tabViews = [
  ...stripComments(readFileSync(home, "utf8")).matchAll(/case \.\w+:\s*\n\s*(\w+View)\(state:/g),
].map((match) => match[1]);
const appFiles = swiftFiles(join(root, "apps/ios"));
const edgeViolations = [];
if (tabViews.length < 3) {
  edgeViolations.push(`HomeView.swift: found only ${tabViews.length} tab views`);
}
for (const view of tabViews) {
  const file = appFiles.find((path) =>
    new RegExp(`\\bstruct ${view}\\b`).test(readFileSync(path, "utf8")),
  );
  if (!file) {
    edgeViolations.push(`${view}: no file declares it`);
    continue;
  }
  const text = stripComments(readFileSync(file, "utf8"));
  const scrolls = text.match(/ScrollView\s*(\{|\(\s*\.vertical)/g)?.length ?? 0;
  const soft = text.match(/\.softScrollEdges\(\)/g)?.length ?? 0;
  if (scrolls === 0 || soft < scrolls) {
    edgeViolations.push(
      `${relative(root, file)}: ${scrolls} vertical scroll views, ${soft} .softScrollEdges()`,
    );
  }
}
for (const file of appFiles) {
  if (/scrollEdgeEffectStyle\(\s*\.hard/.test(stripComments(readFileSync(file, "utf8")))) {
    edgeViolations.push(`${relative(root, file)}: a hard scroll edge`);
  }
}
if (edgeViolations.length > 0) {
  console.error(edgeViolations.join("\n"));
  console.error(
    "Every tab's scroll view fades under the bars with .softScrollEdges() (docs/design-system.md).",
  );
  process.exit(1);
}
