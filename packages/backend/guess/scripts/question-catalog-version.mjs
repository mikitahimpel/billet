// Recomputes `version` in src/question-catalog.json from its questions and writes the file back.
// Run after any change to the questions: `pnpm --filter @billet/backend-guess catalog:version`.
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const file = new URL("../src/question-catalog.json", import.meta.url);
const { questions } = JSON.parse(readFileSync(file, "utf8"));
// The first 16 hex digits of the SHA-256 of the compact JSON of `questions`;
// test/question-catalog.test.ts computes the same and fails when the file's value is stale.
const version = createHash("sha256").update(JSON.stringify(questions)).digest("hex").slice(0, 16);
writeFileSync(file, `${JSON.stringify({ version, questions }, null, 2)}\n`);
console.log(version);
