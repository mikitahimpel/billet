import type { APIRoute } from "astro";
import { appStoreUrl, siteDescription } from "../config";
import { pages, type SitePage } from "../site";

// The llms.txt convention (llmstxt.org): a title, a one-line summary, then links to each page's Markdown twin.
const twin = (page: SitePage, site: URL | undefined) => new URL(`${page.path}index.md`, site).href;
const links = (group: SitePage["group"], site: URL | undefined) =>
  pages
    .filter((page) => page.group === group)
    .map((page) => `- [${page.label}](${twin(page, site)}): ${page.summary}`)
    .join("\n");

export const GET: APIRoute = ({ site }) =>
  new Response(
    `# Ourio

> ${siteDescription}

Ourio is a free iPhone app (iOS 18 or later) for couples, in English on the US App Store. It has no chat, no ads and no in-app purchases. Two partners pair their phones with a 10-character code and share one room, one cat named Mochi, Lock Screen drawings and notes, photo Moments, a planner (countdown, love streak, date night, wishlists, calendar, shared lists, To watch with Pick tonight, Places to go), two games (Who knows who, Draw & guess), a coin shop and six widgets.

- Website: ${new URL("/", site).href}
- App Store: ${appStoreUrl}

## Product

${links("product", site)}

## Features

${links("features", site)}

## Compare

${links("compare", site)}

## Help

${links("help", site)}

## Optional

${links("legal", site)}
`,
    { headers: { "Content-Type": "text/plain; charset=utf-8" } },
  );
