// Tells Bing, Yandex and the other IndexNow engines which URLs changed. Run after a production deploy, with the
// changed URLs only:
//
//   pnpm --filter @billet/landing indexnow https://ourio.app/faq/
//   pnpm --filter @billet/landing indexnow --all        # every URL in the built sitemap, after a site-wide change
//   pnpm --filter @billet/landing indexnow --dry-run
//
// The key is public by design: IndexNow checks it against public/<key>.txt on the live site.
import { readFileSync } from "node:fs";

const host = "ourio.app";
const key = "41e39cb3ae8d5ac7d0259a694de53fc7";

const args = process.argv.slice(2);
const dry = args.includes("--dry-run");
let urls = args.filter((a) => a.startsWith("https://"));
// Bing asks for changed URLs only; resending the whole sitemap on every deploy can get submissions ignored.
if (!urls.length && !args.includes("--all")) {
  throw new Error("pass the changed URLs, or --all after a site-wide change");
}
if (!urls.length) {
  const sitemap = readFileSync(new URL("../dist/sitemap.xml", import.meta.url), "utf8");
  urls = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
}
if (!urls.length) throw new Error("no URLs: build the site first or pass them as arguments");

const body = { host, key, keyLocation: `https://${host}/${key}.txt`, urlList: urls };
if (dry) {
  console.log(JSON.stringify(body, null, 2));
} else {
  const res = await fetch("https://api.indexnow.org/indexnow", {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify(body),
  });
  console.log(`IndexNow: ${res.status} ${res.statusText} for ${urls.length} URLs`);
  if (!res.ok) process.exit(1);
}
