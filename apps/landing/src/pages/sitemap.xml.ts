import type { APIRoute } from "astro";
import { pages } from "../site";

// A handful of pages, listed in site.ts, so a hand-written sitemap instead of @astrojs/sitemap.
export const GET: APIRoute = ({ site }) =>
  new Response(
    `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${pages.map((page) => `  <url><loc>${new URL(page.path, site).href}</loc></url>`).join("\n")}
</urlset>
`,
    { headers: { "Content-Type": "application/xml; charset=utf-8" } },
  );
