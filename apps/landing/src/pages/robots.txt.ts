import type { APIRoute } from "astro";

// One group for every crawler, the search and answer engines named too, so none falls outside it.
// Content-Signal (contentsignals.org): the site may be indexed, quoted in answers and learned from.
const bots = [
  "Googlebot",
  "Bingbot",
  "OAI-SearchBot",
  "ChatGPT-User",
  "GPTBot",
  "PerplexityBot",
  "Perplexity-User",
  "Claude-SearchBot",
  "Claude-User",
  "ClaudeBot",
  "Google-Extended",
  "Applebot",
  "Applebot-Extended",
  "DuckDuckBot",
];

export const GET: APIRoute = ({ site }) =>
  new Response(
    `User-agent: *
${bots.map((bot) => `User-agent: ${bot}`).join("\n")}
Content-Signal: search=yes, ai-input=yes, ai-train=yes
Allow: /

Sitemap: ${new URL("/sitemap.xml", site).href}
`,
    { headers: { "Content-Type": "text/plain; charset=utf-8" } },
  );
