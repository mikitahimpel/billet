// Fails when feature code outside the design package gains a raw `Color(red:`,
// `.font(.system(size:`, numeric corner radius or hand-made "Try again" button, a card whose
// content is not at `CardMetrics.padding`, a scroll view with a hard edge, or a design button restyled
// after its style (docs/design-system.md).
// Baseline counts may only shrink; `--update` rewrites them after a cleanup. Run from anywhere in the
// repository.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");

const roots = ["apps/ios", "packages/ios"];
const skipped = [
  "packages/ios/design/",
  "/.build/",
  "/Tests/",
  "Tests/",
  "Billet.xcodeproj/",
  "/node_modules/",
];
const checks = [
  {
    pattern: /Color\(\s*red:|\.font\(\s*\.system\(\s*size:/g,
    baseline: join(here, "design-baseline.json"),
    what: "raw Color(red:) / .font(.system(size:)",
    fix: "Use Ink colours and the .ourio* text styles from the design package (docs/design-system.md).",
  },
  {
    pattern:
      /\b(?:cornerRadius|(?:top|bottom)(?:Leading|Trailing)Radius)\s*:\s*[\d.]|cardSurface\(\s*radius:\s*[\d.]/g,
    baseline: join(here, "radius-baseline.json"),
    what: "corner radii written as numbers",
    fix: "Corners come from Radius (card, inner, control) or Field / Card (docs/design-system.md#shape).",
  },
  {
    pattern:
      /\b(?:Button|PrimaryButton|SecondaryButton|BilletButton)\(\s*"Try [Aa]gain|(?:Label|Text)\(\s*"[^"]*[Tt]ry again"\s*[,)]/g,
    baseline: join(here, "retry-baseline.json"),
    what: "hand-made Try again buttons",
    fix: "A failed load or send is retried with RetryButton from the design package (docs/design-system.md).",
  },
  {
    pattern:
      /\.padding\((?:\.\w+,\s*)?(?:[1-9]\d*(?:\.\d+)?|0\.\d+)\)|\bspacing:\s*(?:[1-9]\d*(?:\.\d+)?|0\.\d+)\b/g,
    baseline: join(here, "spacing-baseline.json"),
    what: "paddings or spacings written as numbers",
    fix: "Gaps and insets come from Space (xs…xl, gutter, section) or CardMetrics.padding (docs/design-system.md).",
  },
  {
    pattern: /\.buttonStyle\(\s*\.plain\s*\)/g,
    baseline: join(here, "plain-button-baseline.json"),
    what: "buttons with no pressed state (.buttonStyle(.plain))",
    fix: "Use a design button (PrimaryButton, SecondaryButton, ToggleButtonStyle, RetryButton), RowButtonStyle for a row, or PressScaleStyle.",
  },
  {
    pattern:
      /\.font\(\s*\.(?:title[23]?|body|headline|subheadline|caption2?|callout|footnote|largeTitle)\b/g,
    baseline: join(here, "text-style-baseline.json"),
    what: "system text styles instead of the .ourio* styles",
    fix: "Type is the .ourio* text styles from the design package (docs/design-system.md).",
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
    const sorted = Object.fromEntries(
      Object.entries(counts).sort(([a], [b]) => a.localeCompare(b)),
    );
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

// A card's content sits at `CardMetrics.padding`, so `Radius.inner` inside it is concentric with its
// corners. Rows that only pad one axis (lists of rows on a card) are not checked.
const paddingViolations = [];
for (const [file, text] of sources) {
  for (const match of text.matchAll(
    /\.padding\(\s*([^.\s)][^)]*)\)\s*(?:\.frame\([^)]*\)\s*)*\.cardSurface\(/g,
  )) {
    if (match[1].trim() !== "CardMetrics.padding") {
      paddingViolations.push(`${file}: a card padded by ${match[1].trim()}`);
    }
  }
}
if (paddingViolations.length > 0) {
  console.error(paddingViolations.join("\n"));
  console.error(
    "Pad a card's content by CardMetrics.padding, so what is inside it takes Radius.inner (docs/design-system.md#shape).",
  );
  failed = true;
}

// Every vertical scroll view in a file on the design package fades out under the bars and under a
// pinned header: `.softScrollEdges()`, or `.scrollHeader { }`, which applies it. Nothing sets a hard edge.
const edgeViolations = [];
for (const [file, text] of sources) {
  if (/scrollEdgeEffectStyle\(\s*\.hard/.test(text)) {
    edgeViolations.push(`${file}: a hard scroll edge`);
  }
  if (!/^import Design$/m.test(text)) continue;
  const scrolls = text.match(/ScrollView\s*(\{|\(\s*\.vertical)/g)?.length ?? 0;
  const soft = text.match(/\.softScrollEdges\(\)|\.scrollHeader\s*\{/g)?.length ?? 0;
  if (soft < scrolls) {
    edgeViolations.push(`${file}: ${scrolls} vertical scroll views, ${soft} soft edges`);
  }
}
if (edgeViolations.length > 0) {
  console.error(edgeViolations.join("\n"));
  console.error(
    "Every scroll view fades under the bars with .softScrollEdges(), and under a sheet's chips or search with .scrollHeader { } (docs/design-system.md).",
  );
  failed = true;
}

// A design button keeps the package's type and colour: a `.font`, `.tint` or `.foregroundStyle` after
// its style makes a one-off that no longer matches the other buttons.
const restyled = [];
for (const [file, text] of sources) {
  for (const match of text.matchAll(
    /\.buttonStyle\(\s*(Primary|Secondary|Quiet)ButtonStyle\([^)]*\)\s*\)\s*\.(font|tint|foregroundStyle)\(/g,
  )) {
    restyled.push(`${file}: a ${match[1]}ButtonStyle restyled by .${match[2]}`);
  }
}
if (restyled.length > 0) {
  console.error(restyled.join("\n"));
  console.error(
    "Use PrimaryButton, SecondaryButton or QuietButtonStyle as they are; add a variant to the design package if one is missing (docs/design-system.md).",
  );
  failed = true;
}

if (failed) process.exit(1);
