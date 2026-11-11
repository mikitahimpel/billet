// Runs before every static file: Markdown twins by Accept and Link (negotiate.mjs), and the pages.dev hosts kept out
// of search so only the custom domain is indexed. Assets under /_astro/ pass through untouched.

import { serveWithMarkdown } from "../scripts/ai/negotiate.mjs";

export async function onRequest(context) {
  const url = new URL(context.request.url);
  if (url.pathname.startsWith("/_astro/")) return context.next();
  const response = await serveWithMarkdown(context.request, (r) => context.env.ASSETS.fetch(r));
  if (!url.hostname.endsWith(".pages.dev")) return response;
  const hidden = new Response(response.body, response);
  hidden.headers.set("x-robots-tag", "noindex");
  return hidden;
}
