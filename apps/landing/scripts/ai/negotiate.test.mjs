// node --test: which requests get the Markdown twin, and the headers around it.
import assert from "node:assert/strict";
import { test } from "node:test";
import { prefersMarkdown, serveWithMarkdown } from "./negotiate.mjs";

test("Markdown only when asked for explicitly and at least as much as HTML", () => {
  assert.equal(prefersMarkdown("text/markdown"), true);
  assert.equal(prefersMarkdown("text/markdown, text/html;q=0.9"), true);
  assert.equal(prefersMarkdown("text/markdown, text/html, */*"), true);
  assert.equal(prefersMarkdown("text/html, text/markdown;q=0.5"), false);
  assert.equal(prefersMarkdown("text/markdown;q=0"), false);
  assert.equal(prefersMarkdown("text/html,application/xhtml+xml,*/*;q=0.8"), false);
  assert.equal(prefersMarkdown("*/*"), false);
  assert.equal(prefersMarkdown(""), false);
});

const assets = {
  "/pricing/": new Response("<html>", { headers: { "content-type": "text/html" } }),
  "/pricing/index.md": new Response("# Pricing"),
};
const fetchAsset = async (r) =>
  assets[new URL(r.url).pathname]?.clone() ??
  new Response("nope", { status: 404, headers: { "content-type": "text/html" } });
const get = (path, accept) =>
  serveWithMarkdown(
    new Request(`https://example.com${path}`, { headers: accept ? { accept } : {} }),
    fetchAsset,
  );

test("a page names its twin and varies on Accept", async () => {
  const r = await get("/pricing/", "text/html");
  assert.equal(r.headers.get("content-type"), "text/html");
  assert.equal(
    r.headers.get("link"),
    '<https://example.com/pricing/index.md>; rel="alternate"; type="text/markdown"',
  );
  assert.equal(r.headers.get("vary"), "Accept");
});

test("an agent asking for Markdown gets the twin at the page URL", async () => {
  const r = await get("/pricing/", "text/markdown, text/html;q=0.9");
  assert.equal(await r.text(), "# Pricing");
  assert.equal(r.headers.get("content-type"), "text/markdown; charset=utf-8");
  assert.equal(r.headers.get("link"), '<https://example.com/pricing/>; rel="canonical"');
  assert.equal(r.headers.get("x-robots-tag"), "noindex");
});

test("the twin URL itself is Markdown with its page as canonical", async () => {
  const r = await get("/pricing/index.md");
  assert.equal(r.headers.get("content-type"), "text/markdown; charset=utf-8");
  assert.equal(r.headers.get("link"), '<https://example.com/pricing/>; rel="canonical"');
});

test("a page without a twin falls back to HTML", async () => {
  assets["/about/"] = new Response("<html>", { headers: { "content-type": "text/html" } });
  const r = await get("/about/", "text/markdown");
  assert.equal(r.headers.get("content-type"), "text/html");
});

test("a missing page names no twin", async () => {
  const r = await get("/gone/", "text/html");
  assert.equal(r.status, 404);
  assert.equal(r.headers.get("link"), null);
});
