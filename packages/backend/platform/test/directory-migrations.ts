import { env } from "cloudflare:workers";
import { applyPendingAlchemyFormat } from "@alchemy.run/sql/Migrations/AlchemyFormat";
import { splitSqlStatements } from "@alchemy.run/sql/SqlFile";
import type { MigrationRecord, SqlExecutor } from "@alchemy.run/sql/Migrations/Format";
import { MigrationError } from "@alchemy.run/sql/Migrations/Format";
import { Effect } from "effect";

const files = import.meta.glob<string>("../migrations/directory/*/migration.sql", {
  eager: true,
  import: "default",
});

export const directoryMigrationCount = Object.keys(files).length;

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

export const applyDirectoryMigrations = async () =>
  Effect.runPromise(
    applyPendingAlchemyFormat({
      executor,
      table: "__alchemy_migrations",
      records: await records(),
    }),
  );

/** Migrates, then empties every table, in an order the foreign keys allow. */
export const resetDirectory = async () => {
  await applyDirectoryMigrations();
  await env.DB.batch(
    ["push_tokens", "sessions", "devices", "users", "auth_challenges"].map((table) =>
      env.DB.prepare(`DELETE FROM ${table}`),
    ),
  );
};
