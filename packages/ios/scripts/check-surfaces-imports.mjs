// Fails when a Swift file under Sources/Surfaces imports a Feature target.
// docs/architecture.md: Surfaces may import Domain, Ink and DesignSystem, not any feature target.
// A plain `swift build` does not enforce this (see the PR for #3), so ios:build and ios:test run it.
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const sources = join(dirname(fileURLToPath(import.meta.url)), "..", "Sources");
const surfaces = join(sources, "Surfaces");

const featureTargets = new Set(
  readdirSync(sources, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && /^Feature[A-Z]/.test(entry.name))
    .map((entry) => entry.name),
);

// Matches `import X`, `@testable import X`, `public import X`, `import struct X.Y`, `import X.Y`.
const importPattern =
  /^\s*(?:(?:@\w+(?:\([^)]*\))?|(?:public|package|internal|private|fileprivate|open)(?:\([^)]*\))?)\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_]\w*)/;

function swiftFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return swiftFiles(path);
    return entry.name.endsWith(".swift") ? [path] : [];
  });
}

// Blank out comments, keeping newlines so reported line numbers stay right.
function stripComments(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, (match) => match.replace(/[^\n]/g, " "))
    .replace(/\/\/.*$/gm, "");
}

const violations = [];
for (const file of swiftFiles(surfaces)) {
  stripComments(readFileSync(file, "utf8"))
    .split("\n")
    .forEach((line, index) => {
      for (const statement of line.split(";")) {
        const module = importPattern.exec(statement)?.[1];
        if (module !== undefined && featureTargets.has(module)) {
          violations.push(
            `${relative(process.cwd(), file)}:${index + 1}: Surfaces imports ${module}`,
          );
        }
      }
    });
}

if (violations.length > 0) {
  console.error(violations.join("\n"));
  console.error("Surfaces may import Domain, Ink and DesignSystem, not any feature target.");
  process.exit(1);
}
