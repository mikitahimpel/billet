// A built page as Markdown, for answer engines and the AI assistants that read a page for a person (ChatGPT, Claude,
// Perplexity): the page's <main> without the layout, pictures, scripts and controls, links made absolute, under a
// front matter with its title, URL and description. build-markdown.mjs writes one beside every page at <page>/index.md.

import { ELEMENT_NODE, TEXT_NODE, parse } from "ultrahtml";

// Left out with all they hold: what only works or only means something on screen.
const SKIP = new Set([
  "script",
  "style",
  "svg",
  "template",
  "noscript",
  "button",
  "input",
  "select",
  "textarea",
  "output",
  "video",
  "audio",
  "img",
  "picture",
  "iframe",
  "canvas",
  "form",
  "nav",
  "dialog",
]);
const BLOCK = new Set([
  "p",
  "div",
  "section",
  "article",
  "aside",
  "header",
  "footer",
  "figure",
  "figcaption",
  "details",
  "main",
  "dl",
  "dd",
  "label",
  "fieldset",
]);

const ENTITIES = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  mdash: "—",
  ndash: "–",
  hellip: "…",
  rsquo: "’",
  lsquo: "‘",
  rdquo: "”",
  ldquo: "“",
  times: "×",
  middot: "·",
  rarr: "→",
};
const decode = (s) =>
  s.replace(/&(#x[\da-f]+|#\d+|\w+);/gi, (m, e) =>
    e[0] === "#"
      ? String.fromCodePoint(
          e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : Number(e.slice(1)),
        )
      : (ENTITIES[e] ?? m),
  );

const hidden = (n) =>
  "hidden" in n.attributes ||
  n.attributes["aria-hidden"] === "true" ||
  n.attributes["data-md"] === "skip";
const blocks = (s) => `\n\n${s.trim()}\n\n`;
const tidy = (s) =>
  s
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

/** An element's children as Markdown; `url` makes its links absolute. */
function children(node, url) {
  return node.children.map((c) => md(c, url)).join("");
}

function md(node, url) {
  if (node.type === TEXT_NODE) return decode(node.value).replace(/\s+/g, " ");
  if (node.type !== ELEMENT_NODE) return node.children ? children(node, url) : "";
  const name = node.name.toLowerCase();
  if (SKIP.has(name) || hidden(node)) return "";
  const inner = () => children(node, url);
  const inline = () => inner().replace(/\s+/g, " ").trim();
  const heading = /^h([1-6])$/.exec(name);
  // A headline split into words for its animation hides the words and says itself in aria-label.
  if (heading)
    return blocks(
      `${"#".repeat(Number(heading[1]))} ${inline() || decode(node.attributes["aria-label"] ?? "")}`,
    );
  switch (name) {
    case "br":
      return "\n";
    case "a": {
      const href = node.attributes.href;
      const raw = inner();
      const target =
        href && !href.startsWith("#") && !href.startsWith("javascript:")
          ? new URL(decode(href), url).href
          : null;
      // A card made a link: its heading and text as they are, the link after them under the heading's name.
      if (/^#+ /m.test(raw))
        return target
          ? blocks(`${tidy(raw)}\n\n[${raw.match(/^#+ (.+)$/m)[1].trim()}](${target})`)
          : raw;
      const text = inline();
      // Spaced, as links set side by side as buttons have nothing between them; a link to a part of the same
      // page (href="#contact") keeps its text, spaced the same way.
      if (!text) return "";
      return target ? ` [${text}](${target}) ` : ` ${text} `;
    }
    case "strong":
    case "b": {
      const text = inline();
      return text ? ` **${text}** ` : "";
    }
    case "em":
    case "i": {
      const text = inline();
      return text ? ` *${text}* ` : "";
    }
    case "span":
    case "small":
    case "time":
      // Spaced, as spans laid out apart on screen often have nothing between them in the markup.
      return ` ${inner()} `;
    case "code":
      return `\`${inline()}\``;
    case "summary": {
      // A question already set as a heading (<summary><h3>) keeps its own level.
      const raw = inner();
      return /^#+ /m.test(raw) ? blocks(tidy(raw)) : blocks(`### ${inline()}`);
    }
    case "dt":
      return blocks(`**${inline()}**`);
    case "blockquote":
      return blocks(tidy(inner()).replace(/^/gm, "> "));
    case "ul":
    case "ol": {
      const items = node.children.filter(
        (c) => c.type === ELEMENT_NODE && c.name === "li" && !hidden(c),
      );
      const lines = items.map((li, i) => {
        const marker = name === "ol" ? `${i + 1}. ` : "- ";
        return (
          marker +
          tidy(children(li, url))
            .replace(/\n+/g, "\n")
            .replace(/\n/g, `\n${" ".repeat(marker.length)}`)
        );
      });
      return lines.length ? blocks(lines.join("\n")) : "";
    }
    case "table": {
      const rows = [];
      const walk = (n) => {
        for (const c of n.children ?? []) {
          if (c.type !== ELEMENT_NODE) continue;
          if (c.name === "tr")
            rows.push(
              c.children
                .filter((d) => d.type === ELEMENT_NODE && (d.name === "td" || d.name === "th"))
                .map((d) => tidy(children(d, url)).replace(/\s+/g, " ").replace(/\|/g, "\\|")),
            );
          else walk(c);
        }
      };
      walk(node);
      if (!rows.length) return "";
      const width = Math.max(...rows.map((r) => r.length));
      const line = (r) => `| ${Array.from({ length: width }, (_, i) => r[i] ?? "").join(" | ")} |`;
      return blocks(
        [line(rows[0]), line(Array(width).fill("---")), ...rows.slice(1).map(line)].join("\n"),
      );
    }
    default:
      return BLOCK.has(name) ? blocks(inner()) : inner();
  }
}

const attr = (html, re) => decode(html.match(re)?.[1] ?? "");

/**
 * The content of a <meta name=…> tag. HTML minifiers sort attributes and drop their quotes
 * (`<meta content="noindex" name=robots>`), so the tag is read attribute by attribute, not by one fixed shape.
 */
function meta(html, name) {
  for (const [tag] of html.matchAll(/<meta\b[^>]*>/gi)) {
    const attrs = {};
    for (const m of tag.matchAll(/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/g))
      attrs[m[1].toLowerCase()] = m[2] ?? m[3] ?? m[4];
    if (attrs.name?.toLowerCase() === name) return decode(attrs.content ?? "");
  }
  return "";
}

// A tag with its attributes, a quoted value (which may hold '>') consumed whole; then one attribute of it.
const TAG =
  /<([a-zA-Z][\w:-]*)((?:\s+[^\s"'<>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'<>]+))?)*)\s*(\/?)>/g;
const ATTR = /\s+([^\s"'<>/=]+)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s"'<>]+))?/g;

/**
 * Markup with every attribute value in quotes. Minifiers drop the quotes where HTML allows it (`href=/pricing/`),
 * and ultrahtml misreads such a value when it holds a slash or a '#': the link loses its href.
 */
const quoteAttributes = (html) =>
  html.replace(TAG, (_, name, attrs, slash) => {
    const quoted = attrs.replace(ATTR, (_, key, value) =>
      value === undefined
        ? ` ${key}`
        : /^["']/.test(value)
          ? ` ${key}=${value}`
          : ` ${key}="${value}"`,
    );
    return `<${name}${quoted}${slash ? " /" : ""}>`;
  });

/** One built page as Markdown with its front matter, or null for a page search engines are told to skip. */
export function pageToMarkdown(html, url) {
  if (/noindex/i.test(meta(html, "robots"))) return null;
  const title = attr(html, /<title>([^<]*)<\/title>/);
  const description = meta(html, "description");
  const main = html.match(/<main\b[\s\S]*<\/main>/)?.[0];
  if (!main) return null;
  // Markdown's own characters in the text stay as they are: the pages use few, and escaping them all reads worse.
  // Comments go first: ultrahtml drops the text right before one, and React islands put <!-- --> between text runs.
  const body = tidy(md(parse(quoteAttributes(main.replace(/<!--[\s\S]*?-->/g, ""))), url))
    .replace(/ +([.,;:!?)])/g, "$1")
    .replace(/([(]) +/g, "$1")
    .replace(/ {2,}/g, " ");
  const yaml = (s) => JSON.stringify(s);
  return `---\ntitle: ${yaml(title)}\nurl: ${url}\ndescription: ${yaml(description)}\n---\n\n${body}\n`;
}
