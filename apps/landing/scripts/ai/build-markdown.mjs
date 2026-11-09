// After the build: every page also as Markdown at <page>/index.md, for AI agents and answer engines. Each page names
// its twin in <head> with <link rel="alternate" type="text/markdown">; llms.txt links them. astro.config.ts runs this
// when the build is done. Pages without <main>, and pages marked noindex, get no twin.

import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pageToMarkdown } from "./page-to-markdown.mjs";

/** Every built page's path ('/', '/faq/'); '_astro' and other underscore folders are assets. */
function pagesIn(dist) {
  const found = [];
  const walk = (dir, rel) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) {
        if (!name.startsWith("_")) walk(path, `${rel}${name}/`);
      } else if (name === "index.html") found.push(`/${rel}`);
    }
  };
  walk(dist, "");
  return found;
}

/** Writes the twins into `dist` and returns how many it wrote; throws when there is none. */
export function writeMarkdownTwins(dist, site) {
  const origin = site.replace(/\/$/, "");
  let written = 0;
  for (const path of pagesIn(dist)) {
    const markdown = pageToMarkdown(
      readFileSync(join(dist, path, "index.html"), "utf8"),
      `${origin}${path}`,
    );
    if (!markdown) continue;
    writeFileSync(join(dist, path, "index.md"), markdown);
    written++;
  }
  if (written === 0) throw new Error("markdown twins: no page with <main> was built");
  return written;
}
