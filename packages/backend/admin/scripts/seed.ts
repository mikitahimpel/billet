// Seeds made-up pairs for the admin panel (src/seed-data.ts) and writes them as SQL.
//
//   node packages/backend/admin/scripts/seed.ts [--today YYYY-MM-DD] [--weeks 10] [--scale 1]
//     [--out admin-seed.sql] [--local <path to the local D1 .sqlite>]
//
// Without --local it only writes the SQL file, which `wrangler d1 execute <database> --file` runs.
// With --local it also applies it to that SQLite file (the D1 of `pnpm alchemy dev`). It never
// talks to Cloudflare.
import { writeFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { parseArgs } from "node:util";
import { makeSeed, seedSql } from "../src/seed-data.ts";

const { values } = parseArgs({
  options: {
    today: { type: "string", default: new Date().toISOString().slice(0, 10) },
    weeks: { type: "string", default: "10" },
    scale: { type: "string", default: "1" },
    seed: { type: "string", default: "20261104" },
    out: { type: "string", default: "admin-seed.sql" },
    local: { type: "string" },
    "no-build-columns": { type: "boolean", default: false },
  },
});

if (!/^\d{4}-\d{2}-\d{2}$/.test(values.today)) throw new Error("--today must be YYYY-MM-DD");

const seed = makeSeed({
  today: values.today,
  weeks: Number(values.weeks),
  scale: Number(values.scale),
  seed: Number(values.seed),
});
const sql = seedSql(seed, { eventBuild: !values["no-build-columns"] });
writeFileSync(values.out, `${sql}\n`);

const pairs = new Set(seed.members.map(({ pairId }) => pairId)).size;
console.log(
  `${seed.users.length} people, ${pairs} pairs, ${seed.events.length} pair_events rows, ${seed.details.length} event_details rows -> ${values.out}`,
);

if (values.local !== undefined) {
  const db = new DatabaseSync(values.local);
  db.exec("BEGIN");
  try {
    db.exec(sql);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
  db.close();
  console.log(`applied to ${values.local}`);
}
