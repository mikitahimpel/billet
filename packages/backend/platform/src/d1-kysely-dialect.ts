import {
  type CompiledQuery,
  type DatabaseConnection,
  type DatabaseIntrospector,
  type Dialect,
  type Driver,
  type Kysely,
  type QueryResult,
  SqliteAdapter,
  SqliteIntrospector,
  SqliteQueryCompiler,
} from "kysely";

const noTransactions = () =>
  Promise.reject(new Error("D1 has no interactive transactions; use a batch"));

class D1Connection implements DatabaseConnection {
  constructor(private readonly db: D1Database) {}

  async executeQuery<R>(query: CompiledQuery): Promise<QueryResult<R>> {
    const result = await this.db
      .prepare(query.sql)
      .bind(...query.parameters)
      .all<R>();
    const { changes, last_row_id: lastRowId } = result.meta;
    return {
      rows: result.results,
      ...(changes === undefined ? {} : { numAffectedRows: BigInt(changes) }),
      ...(lastRowId === undefined || lastRowId === null ? {} : { insertId: BigInt(lastRowId) }),
    };
  }

  /** D1 has no cursors. Better Auth never streams; Kysely only needs the method to exist. */
  streamQuery<R>(): AsyncIterableIterator<QueryResult<R>> {
    const iterator: AsyncIterableIterator<QueryResult<R>> = {
      next: () => Promise.reject(new Error("D1 does not stream query results")),
      [Symbol.asyncIterator]: () => iterator,
    };
    return iterator;
  }
}

class D1Driver implements Driver {
  private readonly connection: D1Connection;

  constructor(db: D1Database) {
    this.connection = new D1Connection(db);
  }

  init = () => Promise.resolve();
  acquireConnection = () => Promise.resolve(this.connection);
  beginTransaction = noTransactions;
  commitTransaction = noTransactions;
  rollbackTransaction = noTransactions;
  releaseConnection = () => Promise.resolve();
  destroy = () => Promise.resolve();
}

/** Kysely on a D1 binding, for Better Auth. Each query is its own statement: D1 has no sessions. */
export class D1Dialect implements Dialect {
  constructor(private readonly db: D1Database) {}

  createAdapter = () => new SqliteAdapter();
  createDriver = () => new D1Driver(this.db);
  createQueryCompiler = () => new SqliteQueryCompiler();
  createIntrospector = (db: Kysely<unknown>): DatabaseIntrospector => new SqliteIntrospector(db);
}
