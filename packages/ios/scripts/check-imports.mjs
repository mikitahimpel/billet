// Run from one of the Swift packages in packages/ios. Fails when a Swift file under its Sources
// imports a graphics engine: the packages stay engine-free, so the widget never links one.
// A plain `swift build` does not enforce this (see the PR for #3), so ios:build and ios:test run it.
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

const sources = join(process.cwd(), "Sources");

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

function importViolations(files, describe) {
  return files.flatMap((file) =>
    stripComments(readFileSync(file, "utf8"))
      .split("\n")
      .flatMap((line, index) =>
        line.split(";").flatMap((statement) => {
          const module = importPattern.exec(statement)?.[1];
          const problem = module === undefined ? undefined : describe(module);
          return problem === undefined
            ? []
            : [`${relative(process.cwd(), file)}:${index + 1}: ${problem}`];
        }),
      ),
  );
}

const engines = new Set(["RiveRuntime", "RealityKit"]);

const violations = importViolations(swiftFiles(sources), (module) =>
  engines.has(module) ? `imports the engine ${module}` : undefined,
);

if (violations.length > 0) {
  console.error(violations.join("\n"));
  console.error(
    "The packages in packages/ios stay free of graphics engines; RealityKit belongs in apps/ios.",
  );
  process.exit(1);
}
