import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { catalog } from "@billet/contracts-fixtures/catalog";

const goldenDir = join(dirname(fileURLToPath(import.meta.url)), "..", "golden");

/** Sorted keys, two-space indent, trailing newline: byte-stable and diffable. */
const canonical = (value: unknown): string => {
  const sort = (v: unknown): unknown =>
    Array.isArray(v)
      ? v.map(sort)
      : v !== null && typeof v === "object"
        ? Object.fromEntries(
            Object.entries(v)
              .toSorted(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
              .map(([k, x]) => [k, sort(x)]),
          )
        : v;
  return `${JSON.stringify(sort(value), null, 2)}\n`;
};

describe("golden fixtures", () => {
  it("covers every case of every union", () => {
    for (const entry of catalog) {
      if (entry.tags === undefined) continue;
      const seen = new Set(Object.values(entry.samples).map((s) => (s as { _tag: string })._tag));
      expect([...seen].toSorted(), entry.name).toEqual(entry.tags.toSorted());
    }
  });

  it("writes one file per sample, and each decodes and re-encodes to itself", () => {
    rmSync(goldenDir, { recursive: true, force: true });
    for (const entry of catalog) {
      const dir = join(goldenDir, entry.name);
      mkdirSync(dir, { recursive: true });
      for (const [file, sample] of Object.entries(entry.samples)) {
        const encoded = Schema.encodeUnknownSync(entry.schema)(sample);
        const text = canonical(encoded);
        const path = join(dir, `${file}.json`);
        writeFileSync(path, text);

        const decoded = Schema.decodeUnknownSync(entry.schema)(
          JSON.parse(readFileSync(path, "utf8")),
        );
        expect(canonical(Schema.encodeUnknownSync(entry.schema)(decoded)), path).toBe(text);
      }
    }
    expect(readdirSync(goldenDir).toSorted()).toEqual(catalog.map((e) => e.name).toSorted());
  });
});
