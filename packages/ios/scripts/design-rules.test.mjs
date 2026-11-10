import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { codeOnly, rules, scan } from "./design-rules.mjs";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "fixtures", "design");
const components = new Set(["CardHeader", "RowIcon", "Card", "PrimaryButton"]);
const read = (name) => readFileSync(join(fixtures, name), "utf8");

for (const rule of rules) {
  test(`${rule.id}: the failing fixture fails`, () => {
    const { counts } = scan(read(`${rule.id}.fail.swift.fixture`), { components });
    assert.ok((counts[rule.id] ?? 0) > 0, `${rule.id} found nothing`);
  });

  test(`${rule.id}: the passing fixture passes`, () => {
    const { counts, lines } = scan(read(`${rule.id}.pass.swift.fixture`), { components });
    assert.equal(counts[rule.id] ?? 0, 0, `${rule.id} on lines ${lines[rule.id]}`);
  });
}

test("comments and string text are not code, interpolations are", () => {
  const code = codeOnly('let a = "Color.white \\(Color.black)" // Color.red\n/* .shadow( */ x');
  assert.ok(!code.includes("white"));
  assert.ok(code.includes("Color.black"));
  assert.ok(!code.includes("red"));
  assert.ok(!code.includes("shadow"));
  assert.equal(
    code.length,
    'let a = "Color.white \\(Color.black)" // Color.red\n/* .shadow( */ x'.length,
  );
});

test("the failing fixtures report every hit", () => {
  assert.equal(scan(read("padding-literal.fail.swift.fixture")).counts["padding-literal"], 3);
  assert.equal(scan(read("text-role.fail.swift.fixture"), { components }).counts["text-role"], 2);
});
