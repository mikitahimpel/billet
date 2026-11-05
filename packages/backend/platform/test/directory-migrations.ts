import { env } from "cloudflare:workers";
import { applyPendingAlchemyFormat } from "@alchemy.run/sql/Migrations/AlchemyFormat";
import { splitSqlStatements } from "@alchemy.run/sql/SqlFile";
import type { MigrationRecord, SqlExecutor } from "@alchemy.run/sql/Migrations/Format";
import { MigrationError } from "@alchemy.run/sql/Migrations/Format";
import { Effect } from "effect";
import { flagConfigCacheUrl } from "../src/flag-config-repository-live.ts";

const files = import.meta.glob<string>("../migrations/directory/*/migration.sql", {
  eager: true,
  import: "default",
});

export const directoryMigrationCount = Object.keys(files).length;

const sha256 = async (text: string) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

const records = (before?: string): Promise<ReadonlyArray<MigrationRecord>> =>
  Promise.all(
    Object.entries(files)
      .toSorted(([a], [b]) => a.localeCompare(b))
      .filter(([path]) => before === undefined || (path.split("/").at(-2) ?? path) < before)
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

/** Applies every pending migration, or only those named before `before`, as a deploy would. */
export const applyDirectoryMigrations = async (before?: string) =>
  Effect.runPromise(
    applyPendingAlchemyFormat({
      executor,
      table: "__alchemy_migrations",
      records: await records(before),
    }),
  );

/** Migrates, then empties every table, in an order the foreign keys allow. */
export const resetDirectory = async () => {
  await applyDirectoryMigrations();
  await env.DB.batch(
    [
      "pair_events",
      "pair_flags",
      "flag_configs",
      "flag_changes",
      "pair_flag_overrides",
      "pair_members",
      "partner_notices",
      "demo_partners",
      "invites",
      "push_tokens",
      "auth_session",
      "auth_account",
      "auth_verification",
      "auth_user",
      "account_keys",
      "devices",
      "users",
      "auth_challenges",
      "rate_limits",
      "purchases",
      "coin_ledger",
      "app_store_notifications",
      "admin_funnels",
    ].map((table) => env.DB.prepare(`DELETE FROM ${table}`)),
  );
  // The configurations are cached at the edge; a test starts from the empty table, not the cache.
  await caches.default.delete(flagConfigCacheUrl);
};
