import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { describe, expect, it } from "vitest";

// The first request to a Durable Object loads the whole module graph of its Worker, which took
// 4-9 s for the PairRoom graph (Effect, Drizzle) on this machine and timed out the first demo test
// of every file. The demo Worker must stay free of that graph.
const heavy = /from "(effect|drizzle-orm|@effect\/|@billet\/)[^"]*"|room-database|pair-room/;

const graph = (file: string, seen = new Set<string>()): Set<string> => {
  if (seen.has(file)) return seen;
  seen.add(file);
  const source = readFileSync(file, "utf8");
  for (const [, spec] of source.matchAll(/from "(\.[^"]+)"/g)) {
    graph(resolve(dirname(file), spec ?? ""), seen);
  }
  return seen;
};

describe("demo Worker module graph", () => {
  it("imports neither Effect, Drizzle nor the PairRoom modules", () => {
    const files = [...graph(resolve(process.cwd(), "test/demo-worker.ts"))];
    expect(files.length).toBeGreaterThan(3);
    const offenders = files.filter((f) => heavy.test(readFileSync(f, "utf8")));
    expect(offenders).toEqual([]);
  });
});
