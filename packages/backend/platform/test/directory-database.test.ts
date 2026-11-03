import { env } from "cloudflare:workers";
import { Effect, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { StoredUser } from "@billet/backend-auth/auth-repository";
import { openDirectoryDatabase } from "../src/directory-database.ts";
import * as directorySchema from "../src/directory-schema.ts";
import { users } from "../src/directory-schema.ts";
import { applyDirectoryMigrations, directoryMigrationCount } from "./directory-migrations.ts";
import {
  appliedColumns,
  declaredColumns,
  getTableName,
  isBookkeeping,
  tablesOf,
} from "./table-columns.ts";

const history = async () =>
  (await env.DB.prepare("SELECT name FROM __alchemy_migrations").all()).results;

describe("directory migrations", () => {
  it("apply from empty and re-apply as a no-op", async () => {
    const row = { id: "a", createdAt: 1 };

    await applyDirectoryMigrations();
    const applied = await history();
    expect(applied).toHaveLength(directoryMigrationCount);
    expect(applied.length).toBeGreaterThan(0);

    const rows = await Effect.runPromise(
      Effect.scoped(
        Effect.gen(function* () {
          const db = yield* openDirectoryDatabase(env.DB);
          yield* db.insert(users).values(row);
          return yield* db.select().from(users);
        }),
      ),
    );
    expect(rows.map((found) => Schema.decodeUnknownSync(StoredUser)(found))).toEqual([row]);

    await applyDirectoryMigrations();
    expect(await history()).toEqual(applied);
    expect((await env.DB.prepare("SELECT id FROM users").all()).results).toEqual([{ id: "a" }]);
  });

  it("leave the tables and columns the Drizzle schema declares, and no others", async () => {
    await applyDirectoryMigrations();
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
