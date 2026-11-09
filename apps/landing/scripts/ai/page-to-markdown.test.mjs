// node --test: a built page to its Markdown twin.
import assert from "node:assert/strict";
import { test } from "node:test";
import { pageToMarkdown } from "./page-to-markdown.mjs";

const page = (main, head = "") =>
  `<!doctype html><html><head><title>Pricing &amp; plans</title><meta name="description" content="What it costs.">${head}</head><body><header>Menu</header><main>${main}</main><footer>Footer</footer></body></html>`;

test("the twin is the page’s main text under its title, URL and description", () => {
  const md = pageToMarkdown(
    page(
      '<h1>Prices</h1><p>From <strong>$29</strong>, see <a href="/faq/?a=1&amp;b=2">the FAQ</a>.</p>',
    ),
    "https://floorto3d.com/pricing/",
  );
  assert.equal(
    md,
    '---\ntitle: "Pricing & plans"\nurl: https://floorto3d.com/pricing/\ndescription: "What it costs."\n---\n\n# Prices\n\nFrom **$29**, see [the FAQ](https://floorto3d.com/faq/?a=1&b=2).\n',
  );
});

test("pictures, controls, navigation and parts marked to skip are left out", () => {
  const md = pageToMarkdown(
    page(
      '<nav>Home › Pricing</nav><p>Text<img alt="x" src="/a.webp"><button>Go</button><span data-md="skip">Tap</span><span aria-hidden="true">+</span></p><script>x()</script>',
    ),
    "https://floorto3d.com/",
  );
  assert.match(md, /---\n\nText\n$/);
});

test("lists, FAQ questions and cards made links read as Markdown", () => {
  const md = pageToMarkdown(
    page(
      '<ul><li>One</li><li>Two</li></ul><details><summary>Is it free?</summary><p>No.</p></details><a href="/for/agents/"><h3>Agents</h3><p>Listings.</p></a>',
    ),
    "https://floorto3d.com/",
  );
  assert.match(
    md,
    /- One\n- Two\n\n### Is it free\?\n\nNo\.\n\n### Agents\n\nListings\.\n\n\[Agents\]\(https:\/\/floorto3d.com\/for\/agents\/\)\n$/,
  );
});

test("pages kept out of search results have no twin", () => {
  assert.equal(
    pageToMarkdown(
      page("<h1>Gone</h1>", '<meta name="robots" content="noindex">'),
      "https://floorto3d.com/404/",
    ),
    null,
  );
});

test("a headline split into hidden words reads from its aria-label", () => {
  const md = pageToMarkdown(
    page(
      '<h1 aria-label="Plans that sell."><span aria-hidden="true">Plans</span> <span aria-hidden="true">that sell.</span></h1>',
    ),
    "https://insidewalk.app/",
  );
  assert.match(md, /---\n\n# Plans that sell\.\n$/);
});

test("text before an HTML comment is kept", () => {
  const md = pageToMarkdown(
    page("<p><b>Library<!-- -->.</b> <!-- -->A finished take.</p>"),
    "https://jutsustudio.com/",
  );
  assert.match(md, /---\n\n\*\*Library\.\*\* A finished take\.\n$/);
});

test("a minified page, attributes sorted and unquoted, still gives its description and its noindex", () => {
  const html =
    '<html><head><title>Plans</title><meta content="What it costs." name=description></head><body><main><h1>Plans</h1></main></body></html>';
  assert.match(
    pageToMarkdown(html, "https://floorto3d.com/pricing/"),
    /description: "What it costs\."/,
  );
  assert.equal(
    pageToMarkdown(
      html.replace("<title>", '<meta content="noindex, follow" name=robots><title>'),
      "https://floorto3d.com/pricing/",
    ),
    null,
  );
});

test("links keep their href when a minifier took the quotes off it", () => {
  const md = pageToMarkdown(
    page(
      '<p><a href=https://cal.com/a/call rel="noopener noreferrer" target=_blank>Book a call</a> or <a class=x href=/pricing/#plans>see plans</a>.</p>',
    ),
    "https://floorto3d.com/",
  );
  assert.match(
    md,
    /\[Book a call\]\(https:\/\/cal\.com\/a\/call\) or \[see plans\]\(https:\/\/floorto3d\.com\/pricing\/#plans\)\.\n$/,
  );
});

test("buttons that jump within the page keep their words apart", () => {
  assert.match(
    pageToMarkdown(
      page('<p><a href="#contact">Let’s talk</a><a href="#products">See products</a></p>'),
      "https://floorto3d.com/",
    ),
    /\n\nLet’s talk See products\n$/,
  );
});
