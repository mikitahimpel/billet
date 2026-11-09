// Fails when feature code gains a raw `Color(red:` or `.font(.system(size:`, or a corner radius written as a
// number, outside the design package: colours, type and corners come from `Ink`, the `.nooki*` fonts and `Radius`
// (docs/design-system.md). Run from anywhere in the repository.
//
// Files that already had raw values when a guard was added are listed in its baseline with their counts, and may
// only shrink. `node check-design.mjs --update` rewrites the baselines after a cleanup.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");

const roots = ["apps/ios", "packages/ios"];
const skipped = ["packages/ios/design/", "/.build/", "/Tests/", "Tests/", "Billet.xcodeproj/", "/node_modules/"];
const checks = [
  {
    pattern: /Color\(\s*red:|\.font\(\s*\.system\(\s*size:/g,
    baseline: join(here, "design-baseline.json"),
    what: "raw Color(red:) / .font(.system(size:)",
    fix: "Use Ink colours and the .nooki* text styles from the design package (docs/design-system.md).",
  },
  {
    pattern:
      /\b(?:cornerRadius|(?:top|bottom)(?:Leading|Trailing)Radius)\s*:\s*[\d.]|cardSurface\(\s*radius:\s*[\d.]/g,
    baseline: join(here, "radius-baseline.json"),
    what: "corner radii written as numbers",
    fix: "Corners come from Radius (card, inner, control) or Field / Card (docs/design-system.md#shape).",
  },
];

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

const sources = roots.flatMap((base) =>
  swiftFiles(join(root, base)).map((file) => [
    relative(root, file),
    stripComments(readFileSync(file, "utf8")),
  ]),
);

function count(pattern) {
  const counts = {};
  for (const [file, text] of sources) {
    const found = text.match(pattern)?.length ?? 0;
    if (found > 0) counts[file] = found;
  }
  return counts;
}

if (process.argv.includes("--update")) {
  for (const check of checks) {
    const counts = count(check.pattern);
    const sorted = Object.fromEntries(Object.entries(counts).sort(([a], [b]) => a.localeCompare(b)));
    writeFileSync(check.baseline, JSON.stringify(sorted, null, 2) + "\n");
    console.log(`${relative(root, check.baseline)}: ${Object.keys(sorted).length} files`);
  }
  process.exit(0);
}

let failed = false;
for (const check of checks) {
  const baseline = JSON.parse(readFileSync(check.baseline, "utf8"));
  const violations = Object.entries(count(check.pattern)).flatMap(([file, found]) => {
    const allowed = baseline[file] ?? 0;
    return found > allowed ? [`${file}: ${found} ${check.what}, ${allowed} allowed`] : [];
  });
  if (violations.length > 0) {
    console.error(violations.join("\n"));
    console.error(check.fix);
    failed = true;
  }
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
for (const [file, text] of sources) {
  if (/scrollEdgeEffectStyle\(\s*\.hard/.test(text)) {
    edgeViolations.push(`${file}: a hard scroll edge`);
  }
}
if (edgeViolations.length > 0) {
  console.error(edgeViolations.join("\n"));
  console.error(
    "Every tab's scroll view fades under the bars with .softScrollEdges() (docs/design-system.md).",
  );
  failed = true;
}

if (failed) process.exit(1);
