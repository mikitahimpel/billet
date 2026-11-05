// Recomputes `version` in src/date-catalog.json from its ideas and writes the file back.
// Run after any change to the ideas: `pnpm --filter @billet/backend-dates catalog:version`.
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const file = new URL("../src/date-catalog.json", import.meta.url);
const { ideas } = JSON.parse(readFileSync(file, "utf8"));
// The first 16 hex digits of the SHA-256 of the compact JSON of `ideas`; test/date-catalog.test.ts
// computes the same and fails when the file's value is stale.
const version = createHash("sha256").update(JSON.stringify(ideas)).digest("hex").slice(0, 16);
writeFileSync(file, `${JSON.stringify({ version, ideas }, null, 2)}\n`);
console.log(version);
