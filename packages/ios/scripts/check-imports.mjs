// Run from a Swift package in packages/ios. Fails when Sources import a graphics engine (the widget
// must never link one), a Feature imports another Feature, or an Interface imports a feature, views
// or the network. `swift build` enforces none of these.
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

// Keeps newlines so reported line numbers stay right.
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

// An interface target holds value types and protocols only: no views, no network, no feature.
const notInInterfaces = new Set(["Design", "DesignSystem", "Transport", "SwiftUI"]);

function targetOf(file) {
  return relative(sources, file).split("/")[0];
}

// The feature rules of docs/ios-architecture.md: a feature reaches another only through its
// `<X>Interface` target, and an interface target depends on nothing above the layers.
function describe(target, module) {
  if (engines.has(module)) return `imports the engine ${module}`;
  const isFeature = target.startsWith("Feature");
  const isInterface = target.endsWith("Interface");
  if (isFeature && module.startsWith("Feature") && module !== target) {
    return `${target} imports ${module}; a feature imports another only through its Interface`;
  }
  if (isInterface && (module.startsWith("Feature") || notInInterfaces.has(module))) {
    return `${target} imports ${module}; an Interface holds value types and protocols only`;
  }
  return undefined;
}

const violations = swiftFiles(sources).flatMap((file) => {
  const target = targetOf(file);
  return importViolations([file], (module) => describe(target, module));
});

if (violations.length > 0) {
  console.error(violations.join("\n"));
  console.error(
    "The packages in packages/ios stay free of graphics engines (RealityKit belongs in " +
      "apps/ios), and features meet only through their Interface targets " +
      "(docs/ios-architecture.md).",
  );
  process.exit(1);
}
