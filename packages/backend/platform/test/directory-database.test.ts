import { env } from "cloudflare:workers";
import { applyPendingAlchemyFormat } from "@alchemy.run/sql/Migrations/AlchemyFormat";
import { splitSqlStatements } from "@alchemy.run/sql/SqlFile";
import type { MigrationRecord, SqlExecutor } from "@alchemy.run/sql/Migrations/Format";
import { MigrationError } from "@alchemy.run/sql/Migrations/Format";
import { Effect, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { openDirectoryDatabase } from "../src/directory-database.ts";
import * as directorySchema from "../src/directory-schema.ts";
import { directoryProbe } from "../src/directory-schema.ts";
import { PlatformProbe } from "../src/platform-probe.ts";
import {
  appliedColumns,
  declaredColumns,
  getTableName,
  isBookkeeping,
  tablesOf,
} from "./table-columns.ts";

const files = import.meta.glob<string>("../migrations/directory/*/migration.sql", {
  eager: true,
  import: "default",
});

const sha256 = async (text: string) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

const records = (): Promise<ReadonlyArray<MigrationRecord>> =>
  Promise.all(
    Object.entries(files)
      .toSorted(([a], [b]) => a.localeCompare(b))
      .map(async ([path, sql]) => ({
        name: path.split("/").at(-2) ?? path,
        hash: await sha256(sql),
        createdAtMillis: undefined,
        sql,
        statements: splitSqlStatements(sql),
      })),
  );

const failed = (cause: unknown) => new MigrationError({ message: String(cause), cause });

// The steps `alchemy deploy` runs against D1, through a binding instead of the Cloudflare API.
const executor: SqlExecutor = {
  dialect: "sqlite",
  query: (sql, params = []) =>
    Effect.tryPromise({
      try: async () =>
        (
          await env.DB.prepare(sql)
            .bind(...params)
            .all()
        ).results,
      catch: failed,
    }),
  batch: (statements) =>
    Effect.tryPromise({
      try: () => env.DB.batch(statements.map((sql) => env.DB.prepare(sql))).then(() => undefined),
      catch: failed,
    }),
};

const applyAll = async () =>
  Effect.runPromise(
    applyPendingAlchemyFormat({
      executor,
      table: "__alchemy_migrations",
      records: await records(),
    }),
  );

const history = async () =>
  (await env.DB.prepare("SELECT name FROM __alchemy_migrations").all()).results;

describe("directory migrations", () => {
  it("apply from empty and re-apply as a no-op", async () => {
    const row = { id: "a", createdAt: 1 };

    await applyAll();
    const applied = await history();
    expect(applied).toHaveLength(Object.keys(files).length);
    expect(applied.length).toBeGreaterThan(0);

    const rows = await Effect.runPromise(
      Effect.scoped(
        Effect.gen(function* () {
          const db = yield* openDirectoryDatabase(env.DB);
          yield* db.insert(directoryProbe).values(row);
          return yield* db.select().from(directoryProbe);
        }),
      ),
    );
    expect(rows.map((found) => Schema.decodeUnknownSync(PlatformProbe)(found))).toEqual([row]);

    await applyAll();
    expect(await history()).toEqual(applied);
    expect((await env.DB.prepare("SELECT id FROM directory_probe").all()).results).toEqual([
      { id: "a" },
    ]);
  });

  it("leave the tables and columns the Drizzle schema declares, and no others", async () => {
    await applyAll();
    const tables = tablesOf(directorySchema);
    const names = (
      await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all<{
        name: string;
      }>()
    ).results
      .map(({ name }) => name)
      .filter((name) => !isBookkeeping(name));
    expect(names.toSorted()).toEqual(tables.map(getTableName).toSorted());

    for (const table of tables) {
      const info = await env.DB.prepare(`PRAGMA table_info(${getTableName(table)})`).all<{
        name: string;
        type: string;
        notnull: number;
        pk: number;
      }>();
      expect(appliedColumns(info.results)).toEqual(declaredColumns(table));
    }
  });
});
