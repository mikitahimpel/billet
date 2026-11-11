import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

// The design rules for feature code (docs/design-system.md#rules): every rule counts the places a
// file reaches past the design package. `check-design.mjs` runs them over the app and the feature
// packages against a baseline that may only shrink.

/** Blanks comments and the text of string literals (interpolations stay code), keeping offsets. */
export function codeOnly(text) {
  const out = text.split("");
  const blank = (from, to) => {
    for (let k = from; k < to; k++) if (out[k] !== "\n") out[k] = " ";
  };
  // Each entry is an open string: its delimiter and, while in an interpolation, the paren depth.
  const strings = [];
  let i = 0;
  while (i < text.length) {
    const top = strings[strings.length - 1];
    if (top && top.depth === 0) {
      if (text[i] === "\\" && text[i + 1] === "(") {
        blank(i, i + 2);
        top.depth = 1;
        i += 2;
      } else if (text[i] === "\\") {
        blank(i, i + 2);
        i += 2;
      } else if (text.startsWith(top.quote, i)) {
        strings.pop();
        i += top.quote.length;
      } else {
        blank(i, i + 1);
        i += 1;
      }
      continue;
    }
    if (text.startsWith("//", i)) {
      const end = text.indexOf("\n", i);
      const stop = end === -1 ? text.length : end;
      blank(i, stop);
      i = stop;
    } else if (text.startsWith("/*", i)) {
      let depth = 1;
      let j = i + 2;
      while (j < text.length && depth > 0) {
        if (text.startsWith("/*", j)) (depth++, (j += 2));
        else if (text.startsWith("*/", j)) (depth--, (j += 2));
        else j++;
      }
      blank(i, j);
      i = j;
    } else if (text[i] === '"') {
      const quote = text.startsWith('"""', i) ? '"""' : '"';
      strings.push({ quote, depth: 0 });
      i += quote.length;
    } else {
      if (top) {
        if (text[i] === "(") top.depth++;
        if (text[i] === ")" && --top.depth === 0) blank(i, i + 1);
      }
      i++;
    }
  }
  return out.join("");
}

const named = (names) => names.join("|");
const systemColors = named([
  "white",
  "black",
  "gray",
  "red",
  "green",
  "blue",
  "orange",
  "yellow",
  "pink",
  "purple",
  "teal",
  "cyan",
  "mint",
  "indigo",
  "brown",
]);

/**
 * Each rule: `id`, what a hit is, how to fix it, and either a `pattern` over code (comments and
 * string text blanked) or a `find(code, context)` returning match offsets.
 */
export const rules = [
  {
    id: "raw-color",
    what: "raw colours",
    fix: "Colours are Ink.* and Color.honey; art keeps its own palette in an allowed file.",
    pattern: new RegExp(
      String.raw`\bColor\(\s*(?:red|white|hue|hex|uiColor|cgColor)\s*:` +
        String.raw`|\bColor\.(?:${systemColors})\b` +
        String.raw`|\.(?:foregroundStyle|foregroundColor|background|fill|tint|stroke)\(\s*\.(?:${systemColors})\b`,
      "g",
    ),
  },
  {
    id: "raw-font",
    what: "fonts that are not a .ourio* text style",
    fix: "Type is .font(.ourio*) (or .ourioScaledFont for a glyph); nothing else sets a font.",
    pattern: /\.font\(\s*(?!\.ourio)\S|\bFont\.(?:custom|system)\(|\.fontWeight\(|\.fontDesign\(/g,
  },
  {
    id: "padding-literal",
    what: "paddings written as numbers",
    fix: "Spacing is Space.*, CardMetrics.padding, or the padding a design component already has.",
    pattern: /\.padding\(\s*(?:\.[A-Za-z]+\s*,\s*|\[[^\]]*\]\s*,\s*)?-?\d|\bEdgeInsets\(/g,
  },
  {
    id: "frame-literal",
    what: "heights written as numbers",
    fix: "Controls take their height from the design component (Size.button, Size.control, Size.row).",
    pattern: /\.frame\([^)]*\b(?:height|minHeight|maxHeight)\s*:\s*\d/g,
  },
  {
    id: "corner-shape",
    what: "hand-made corners (cornerRadius, RoundedRectangle, clipShape(.rect(cornerRadius:)))",
    fix: "Corners come from Card, .cardSurface(), Field, or .corners(.card / .inner / .control).",
    pattern:
      /\.cornerRadius\(|\bRoundedRectangle\(|\.clipShape\(\s*\.rect\(\s*cornerRadius|\.rect\(\s*cornerRadius|UnevenRoundedRectangle\(/g,
  },
  {
    id: "shadow",
    what: "shadows",
    fix: "No shadow of our own on a card or on glass; a surface that floats is Toast or glass(_:role:).",
    pattern: /\.shadow\(/g,
  },
  {
    id: "flat-surface",
    what: "flat fills on content (cornerFill, Ink.surface, Ink.surfaceRaised, listRowBackground)",
    fix: "Content sits on .cardSurface() (Card, GroupedSection, ItemCard); a recess in a card is .wellSurface(), a round control RoundButton, a bar ProgressBar (docs/design/one-system.md).",
    pattern:
      /\.cornerFill\(|\.listRowBackground\(|(?<!\.listRowBackground\(\s*)\bInk\.surface(?:Raised)?\b/g,
  },
  {
    id: "raw-stroke",
    what: "strokes of our own",
    fix: "A card's edge, a well's and a selected ring are the design package's (cardSurface(state:), .wellSurface()); a line between rows is Hairline.",
    // Called on a shape or a drawing context; an enum case named `.stroke(` is not one.
    pattern: /(?<=[)\]}]\s*|\w|\w[ \t]*\n\s*)\.stroke(?:Border)?\(/g,
  },
  {
    id: "blur-material",
    what: "blurs and materials",
    fix: "Floating surfaces are glass(_:role:); a sheet's ground is BilletSheet's.",
    pattern:
      /\.blur\(|\b(?:ultraThin|thin|regular|thick|ultraThick|bar)Material\b|\bMaterial\.|\.glassEffect\(|\.backgroundStyle\(/g,
  },
  {
    id: "geometry-reader",
    what: "GeometryReader layouts",
    fix: "Lay out with the design primitives (Screen, ItemGrid, ActionRow, CardActions); measure with onGeometryChange.",
    pattern: /\bGeometryReader\b/g,
  },
  {
    id: "button-style",
    what: "system or plain button styling",
    fix: "Buttons are PrimaryButton, SecondaryButton, RetryButton, PriceButton, GlassIconButton or a design ButtonStyle.",
    pattern:
      /\.buttonStyle\(\s*\.(?:plain|borderless|bordered|borderedProminent|glass|glassProminent|automatic)\b|\.buttonBorderShape\(|\.controlSize\(/g,
  },
  {
    id: "tip",
    what: "TipKit hints drawn without the app's Hint style",
    fix: "Show a hint with .hint(tip, arrowEdge:, target:), which draws HintStyle and its ring.",
    pattern: /\.popoverTip\(|\bTipView\(|\.tipViewStyle\(|\.tipBackground\(/g,
  },
  {
    id: "text-role",
    what: "Text without a text style",
    fix: "Give the Text, or the stack around it, a .font(.ourio*), or put it in a design component.",
    find: textWithoutRole,
  },
];

const openers = { "(": ")", "{": "}", "[": "]" };

function closing(code, at) {
  const open = code[at];
  const close = openers[open];
  let depth = 0;
  for (let k = at; k < code.length; k++) {
    if (code[k] === open) depth++;
    else if (code[k] === close && --depth === 0) return k;
  }
  return code.length - 1;
}

/** The modifiers chained after the expression that ends at `end`, as source text. */
function chainAfter(code, end) {
  let k = end + 1;
  let chain = "";
  for (;;) {
    const rest = code.slice(k);
    const dot = /^\s*\.[A-Za-z_]\w*/.exec(rest);
    const trailing = /^[ \t]*\{/.exec(rest);
    const label = /^\s*[A-Za-z_]\w*\s*:\s*\{/.exec(rest);
    if (dot) {
      k += dot[0].length;
      chain += dot[0];
      const call = /^\s*[({]/.exec(code.slice(k));
      if (call) {
        const start = k + call[0].length - 1;
        const stop = closing(code, start);
        chain += code.slice(k, stop + 1);
        k = stop + 1;
        // A call may end with a trailing closure: `.overlay(alignment: .top) { }`.
        const more = /^[ \t]*\{/.exec(code.slice(k));
        if (more) {
          const after = closing(code, k + more[0].length - 1);
          k = after + 1;
        }
      }
    } else if (trailing || label) {
      const match = trailing ?? label;
      k = closing(code, k + match[0].length - 1) + 1;
    } else {
      return chain;
    }
  }
}

/** The name of the call whose argument list or trailing closure opens at `at`. */
function callee(code, at) {
  let k = at - 1;
  for (;;) {
    while (k >= 0 && /\s/.test(code[k])) k--;
    if (code[k] === ")") {
      let depth = 0;
      for (; k >= 0; k--) {
        if (code[k] === ")") depth++;
        else if (code[k] === "(" && --depth === 0) break;
      }
      k--;
      continue;
    }
    if (code[k] === ":") {
      // A labelled trailing closure: step over `label:` and the closures before it.
      k--;
      while (k >= 0 && /\w/.test(code[k])) k--;
      while (k >= 0 && /\s/.test(code[k])) k--;
      if (code[k] === "}") {
        let depth = 0;
        for (; k >= 0; k--) {
          if (code[k] === "}") depth++;
          else if (code[k] === "{" && --depth === 0) break;
        }
        k--;
        continue;
      }
      if (code[k] === ",") return "";
      continue;
    }
    break;
  }
  const end = k + 1;
  while (k >= 0 && /[\w.]/.test(code[k])) k--;
  return code.slice(k + 1, end);
}

const roleGivers =
  /\.font\(|\.ourioScaledFont\(|\.buttonStyle\(\s*(?!\.)|\.labelStyle\(|\.tipViewStyle\(/;

function textWithoutRole(code, context = {}) {
  const components = context.components ?? new Set();
  const hits = [];
  for (const match of code.matchAll(/(?<![\w.])Text\(/g)) {
    const open = match.index + match[0].length - 1;
    if (
      !roleGivers.test(chainAfter(code, closing(code, open))) &&
      !roleAround(code, match.index, components)
    ) {
      hits.push(match.index);
    }
  }
  return hits;
}

/** Whether a call or closure around `at` gives its text a style, up to the declaration it is in. */
function roleAround(code, at, components) {
  for (
    let enclosing = enclosingOpen(code, at);
    enclosing >= 0;
    enclosing = enclosingOpen(code, enclosing)
  ) {
    if (components.has(callee(code, enclosing).split(".").pop())) return true;
    if (
      code[enclosing] === "{" &&
      /^(?:struct|func|var|init|extension|class|enum|protocol)\b/.test(
        precedingKeyword(code, enclosing),
      )
    ) {
      return false;
    }
    if (roleGivers.test(chainAfter(code, closing(code, enclosing)))) return true;
  }
  return false;
}

function enclosingOpen(code, at) {
  let depth = 0;
  for (let k = at - 1; k >= 0; k--) {
    const c = code[k];
    if (c === "}" || c === ")" || c === "]") depth++;
    else if (c === "{" || c === "(" || c === "[") {
      if (depth === 0) return k;
      depth--;
    }
  }
  return -1;
}

/** The declaration keyword of the line a brace opens on, for `var body: some View {` and the like. */
function precedingKeyword(code, at) {
  const lineStart = code.lastIndexOf("\n", at) + 1;
  const line = code.slice(lineStart, at).trim();
  if (!/\{$/.test(code.slice(lineStart, at + 1).trim())) return "";
  return line.replace(
    /^(?:@\w+(?:\([^)]*\))?\s+|(?:public|private|fileprivate|internal|static|nonisolated|override|mutating)\s+)*/,
    "",
  );
}

/** Counts per rule for one file's source. */
export function scan(text, context = {}) {
  const code = codeOnly(text);
  const counts = {};
  const lines = {};
  for (const rule of rules) {
    const offsets = rule.find
      ? rule.find(code, context)
      : [...code.matchAll(rule.pattern)].map((m) => m.index);
    if (offsets.length === 0) continue;
    counts[rule.id] = offsets.length;
    lines[rule.id] = offsets.map((offset) => code.slice(0, offset).split("\n").length);
  }
  return { counts, lines };
}

/** The public view types of the design package, which give their text a role. */
export function designComponents(sources) {
  const names = new Set();
  for (const text of sources) {
    for (const m of text.matchAll(/public struct (\w+)/g)) names.add(m[1]);
  }
  return names;
}

const featureRoots = ["apps/ios/Nooki", "packages/ios/features/Sources"];

function swiftFilesUnder(root, dir) {
  const path = join(root, dir);
  if (!existsSync(path)) return [];
  return readdirSync(path, { withFileTypes: true }).flatMap((entry) => {
    const rel = `${dir}/${entry.name}`;
    if (entry.isDirectory()) return swiftFilesUnder(root, rel);
    return entry.name.endsWith(".swift") ? [rel] : [];
  });
}

const sorted = (object) =>
  Object.fromEntries(Object.entries(object).sort(([a], [b]) => a.localeCompare(b)));

/**
 * Runs every rule over the feature code. A file may have at most its baseline count for a rule;
 * paths in the allow-list are exempt from it. Both live in the design package
 * (`packages/ios/design/lint/`): the baseline may only shrink, and the allow-list may only grow
 * in a change that also changes the design package's sources. Returns the problems found.
 */
export function checkFeatureRules({ root, update = false, base = null }) {
  const lint = join(root, "packages/ios/design/lint");
  const baselinePath = join(lint, "baseline.json");
  const allowPath = join(lint, "allow.json");
  const allow = JSON.parse(readFileSync(allowPath, "utf8"));
  const baseline = existsSync(baselinePath) ? JSON.parse(readFileSync(baselinePath, "utf8")) : {};
  const components = designComponents(
    swiftFilesUnder(root, "packages/ios/design/Sources").map((file) =>
      readFileSync(join(root, file), "utf8"),
    ),
  );

  const found = Object.fromEntries(rules.map((rule) => [rule.id, {}]));
  const lines = {};
  for (const file of featureRoots.flatMap((dir) => swiftFilesUnder(root, dir))) {
    const result = scan(readFileSync(join(root, file), "utf8"), { components });
    for (const [id, count] of Object.entries(result.counts)) {
      if ((allow[id] ?? []).some((prefix) => file.startsWith(prefix))) continue;
      found[id][file] = count;
      lines[`${id} ${file}`] = result.lines[id];
    }
  }

  if (update) {
    // Never raises a count: a cleanup lowers the baseline, nothing raises it.
    const next = {};
    for (const rule of rules) {
      const counts = {};
      for (const [file, count] of Object.entries(found[rule.id])) {
        const allowed = baseline[rule.id]?.[file] ?? (existsSync(baselinePath) ? 0 : count);
        const kept = Math.min(count, allowed);
        if (kept > 0) counts[file] = kept;
      }
      next[rule.id] = sorted(counts);
    }
    writeFileSync(baselinePath, JSON.stringify(next, null, 2) + "\n");
    return [];
  }

  const problems = [];
  for (const rule of rules) {
    const violations = Object.entries(found[rule.id]).flatMap(([file, count]) => {
      const allowed = baseline[rule.id]?.[file] ?? 0;
      if (count <= allowed) return [];
      const at = lines[`${rule.id} ${file}`].join(", ");
      return [`${file}: ${count} ${rule.what}, ${allowed} allowed (lines ${at})`];
    });
    if (violations.length > 0) problems.push([...violations, `  ${rule.fix}`].join("\n"));
  }

  if (base) problems.push(...shrinkOnly({ root, base, baseline, allow }));
  return problems;
}

/** Compares the baseline and allow-list with their state at `base` (a commit). */
function shrinkOnly({ root, base, baseline, allow }) {
  const show = (path) => {
    try {
      return JSON.parse(
        execFileSync("git", ["show", `${base}:${path}`], {
          cwd: root,
          encoding: "utf8",
          stdio: ["ignore", "pipe", "ignore"],
        }),
      );
    } catch {
      return null;
    }
  };
  const problems = [];
  const before = show("packages/ios/design/lint/baseline.json");
  if (before) {
    for (const [id, files] of Object.entries(baseline)) {
      // A rule the base did not have yet starts from what it finds.
      if (!(id in before)) continue;
      for (const [file, count] of Object.entries(files)) {
        const was = before[id]?.[file] ?? 0;
        if (count > was) {
          problems.push(
            `baseline.json raises ${id} for ${file} from ${was} to ${count}; it may only shrink.`,
          );
        }
      }
    }
  }
  const allowBefore = show("packages/ios/design/lint/allow.json");
  if (allowBefore) {
    const added = Object.entries(allow).flatMap(([id, paths]) =>
      paths
        .filter((path) => !(allowBefore[id] ?? []).includes(path))
        .map((path) => `${id} ${path}`),
    );
    if (added.length > 0) {
      const changed = execFileSync(
        "git",
        ["diff", "--name-only", base, "--", "packages/ios/design/Sources"],
        {
          cwd: root,
          encoding: "utf8",
        },
      ).trim();
      if (!changed) {
        problems.push(
          `allow.json adds ${added.join(", ")} without a change to the design package; give the design package the component that makes the exception unneeded, or change it in the same PR.`,
        );
      }
    }
  }
  return problems;
}
