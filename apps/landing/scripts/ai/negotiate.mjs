// Serving a page's Markdown twin (<page>/index.md, written by build-markdown.mjs) to AI agents, at the page's own URL
// for clients that ask for text/markdown, and naming the twin in every page's Link header. Same URL, same content,
// another format, declared with Vary: Accept: standard HTTP content negotiation, not cloaking.
// Used by worker.js (Cloudflare Workers static assets) and pages-middleware.js (Cloudflare Pages Functions).

/** The q-value an Accept header gives a media type: its own entry, else type/*, else * / *, else 0. */
function quality(accept, type) {
  const [major] = type.split("/");
  let exact = null;
  let group = null;
  let any = null;
  for (const part of accept.split(",")) {
    const [range, ...params] = part.trim().toLowerCase().split(";");
    const q = params.map((p) => p.trim()).find((p) => p.startsWith("q="));
    const value = q ? Number(q.slice(2)) : 1;
    const v = Number.isFinite(value) ? value : 0;
    if (range === type) exact = Math.max(exact ?? 0, v);
    else if (range === `${major}/*`) group = Math.max(group ?? 0, v);
    else if (range === "*/*") any = Math.max(any ?? 0, v);
  }
  return exact ?? group ?? any ?? 0;
}

/**
 * Whether a request asks for Markdown at least as much as for HTML. Only an explicit text/markdown counts, so a
 * browser's `*\/*` never gets Markdown; `text/markdown;q=0` is a refusal.
 */
export function prefersMarkdown(accept) {
  if (!accept || !/text\/markdown/i.test(accept)) return false;
  const markdown = quality(accept, "text/markdown");
  return markdown > 0 && markdown >= quality(accept, "text/html");
}

/** Path of a page's twin: '/pricing/' → '/pricing/index.md'. Pages are directories (Astro's default build.format). */
export const twinOf = (path) => `${path}index.md`;

/** The twin as a response: Markdown, its page as canonical, kept out of search results. */
export function markdownResponse(twin, pagePath, url) {
  const response = new Response(twin.body, twin);
  response.headers.set("content-type", "text/markdown; charset=utf-8");
  response.headers.set("link", `<${new URL(pagePath, url)}>; rel="canonical"`);
  response.headers.set("x-robots-tag", "noindex");
  response.headers.append("vary", "Accept");
  return response;
}

/** An HTML page with its twin named in a Link header, for fetchers that never parse the HTML. A 404 page has no twin. */
export function withMarkdownLink(response, url) {
  if (
    !response.ok ||
    !url.pathname.endsWith("/") ||
    !response.headers.get("content-type")?.startsWith("text/html")
  )
    return response;
  const page = new Response(response.body, response);
  page.headers.append(
    "link",
    `<${new URL(twinOf(url.pathname), url)}>; rel="alternate"; type="text/markdown"`,
  );
  page.headers.append("vary", "Accept");
  return page;
}

/**
 * The whole exchange around a static-assets fetch: `fetchAsset(request)` is env.ASSETS.fetch (Workers) or
 * env.ASSETS.fetch / context.next() (Pages). Returns the response to send.
 */
export async function serveWithMarkdown(request, fetchAsset) {
  const url = new URL(request.url);
  if (request.method === "GET" || request.method === "HEAD") {
    if (url.pathname.endsWith("/") && prefersMarkdown(request.headers.get("accept"))) {
      const twin = await fetchAsset(new Request(new URL(twinOf(url.pathname), url), request));
      if (twin.ok) return markdownResponse(twin, url.pathname, url);
    }
    if (url.pathname.endsWith("/index.md")) {
      const twin = await fetchAsset(request);
      return twin.ok
        ? markdownResponse(twin, url.pathname.slice(0, -"index.md".length), url)
        : twin;
    }
  }
  return withMarkdownLink(await fetchAsset(request), url);
}
