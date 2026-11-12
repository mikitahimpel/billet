// public/ is copied as is, under stable names that a long cache would keep stale; only files that must keep
// their name live there. Everything else goes in src/assets, where the build puts a content hash in its name.
import { readdirSync } from "node:fs";

const allowed = new Set([
  "_headers",
  "favicon.png",
  "apple-touch-icon.png",
  "og.png",
  "robots.txt",
  "site.webmanifest",
]);
const stray = readdirSync(new URL("../public/", import.meta.url)).filter(
  (name) => !allowed.has(name),
);

if (stray.length > 0) {
  console.error(
    `public/ holds ${stray.join(", ")}: assets go in src/assets so the build hashes their names`,
  );
  process.exit(1);
}
