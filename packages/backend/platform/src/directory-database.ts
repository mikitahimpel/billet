import * as D1Client from "@effect/sql-d1/D1Client";
import { makeWithDefaults } from "drizzle-orm/effect-d1";
import { Effect, Layer } from "effect";

/** Must not import `alchemy` (docs/alchemy.md). Lives in the caller's `Scope`: once per request. */
export const openDirectoryDatabase = (db: D1Database) =>
  Effect.gen(function* () {
    const services = yield* Layer.build(D1Client.layer({ db }));
    return yield* makeWithDefaults({}).pipe(Effect.provideContext(services));
  }).pipe(Effect.orDie);

export type DirectoryDatabase = Effect.Success<ReturnType<typeof openDirectoryDatabase>>;

interface Compilable {
  readonly toSQL: () => { readonly sql: string; readonly params: ReadonlyArray<unknown> };
}

/** D1 has no interactive transactions, so a statement can't depend on an earlier result in JS. */
export const atomically = (db: DirectoryDatabase, statements: ReadonlyArray<Compilable>) =>
  db.$client.batch(
    statements.map((statement) => {
      const { sql, params } = statement.toSQL();
      return db.$client.unsafe(sql, params);
    }),
  );
