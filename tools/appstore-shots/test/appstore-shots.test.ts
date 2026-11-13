import assert from "node:assert/strict";
import { test } from "node:test";
import { tokenDrift } from "../src/check-tokens.ts";
import { headlineHtml, loadManifest, manifestProblems } from "../src/manifest.ts";
import { flattenToRgb, pngInfo } from "../src/png.ts";
import { deflateSync } from "node:zlib";

const manifest = (locale: string) =>
  loadManifest(new URL(`../manifest/${locale}.json`, import.meta.url).pathname);

test("the tokens match Palette.swift", () => {
  assert.deepEqual(tokenDrift(), []);
});

test("a drifted token is reported", () => {
  assert.equal(tokenDrift("let nothing = 1").length > 0, true);
});

for (const locale of ["en", "ru"]) {
  test(`the ${locale} manifest is well formed`, () => {
    assert.deepEqual(
      manifestProblems(manifest(locale), () => true),
      [],
    );
    assert.equal(manifest(locale).panels.length, 8);
  });
}

test("the accent word is wrapped", () => {
  assert.equal(headlineHtml("One {list} <b>"), 'One <span class="accent">list</span> &lt;b&gt;');
});

test("an RGBA PNG becomes RGB of the same size", () => {
  const width = 3;
  const height = 2;
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header.set([8, 6, 0, 0, 0], 8);
  const rows = Buffer.concat(
    [0, 1].map(() => Buffer.concat([Buffer.from([0]), Buffer.alloc(width * 4, 255)])),
  );
  const chunk = (type: string, body: Buffer) => {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(body.length);
    return Buffer.concat([length, Buffer.from(type), body, Buffer.alloc(4)]);
  };
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
  const flat = pngInfo(flattenToRgb(png));
  assert.deepEqual(flat, { width, height, colorType: 2 });
});
