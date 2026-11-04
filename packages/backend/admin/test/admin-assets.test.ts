import { describe, expect, it } from "vitest";
import { adminCss, adminHtml, adminJs, adminLibJs } from "../src/admin-assets.ts";
import css from "../web/app.css?raw";
import html from "../web/index.html?raw";

// The scripts are ES modules, so their text is loaded the same way but read off `default`.
const raw = async (load: Promise<{ default: string }>) => (await load).default;
const js = await raw(import("../web/app.js?raw"));
const lib = await raw(import("../web/lib.js?raw"));

describe("the generated assets", () => {
  it("match web/ (run `pnpm assets` after changing it)", () => {
    expect(adminHtml).toBe(html);
    expect(adminCss).toBe(css);
    expect(adminJs).toBe(js);
    expect(adminLibJs).toBe(lib);
  });

  it("route every section in the nav", () => {
    const routes = [...adminHtml.matchAll(/data-route="([a-z]+)"/g)].map(([, name]) => name);
    expect(routes).toContain("maintenance");
    const table = adminJs.slice(adminJs.indexOf("const ROUTES = {"));
    for (const name of routes) expect(table).toMatch(new RegExp(`\\n\\s+${name}: render`));
  });

  it("need nothing the Content Security Policy forbids", () => {
    expect(adminHtml).not.toMatch(/<script(?![^>]*\ssrc=)/);
    expect(adminHtml).not.toMatch(/<style|\sstyle=|\son[a-z]+=/i);
    expect(`${adminJs}\n${adminLibJs}`).not.toMatch(
      /innerHTML|outerHTML|insertAdjacentHTML|eval\(|new Function|document\.write/,
    );
    for (const asset of [adminHtml, adminCss, adminJs, adminLibJs])
      expect(asset).not.toMatch(/https?:\/\/(?!www\.w3\.org)/);
  });
});
