import { getTableColumns, getTableName, is } from "drizzle-orm";
import { getTableConfig, SQLiteTable } from "drizzle-orm/sqlite-core";

export interface ColumnInfo {
  readonly name: string;
  readonly type: string;
  readonly notNull: boolean;
  readonly primaryKey: boolean;
}

const byName = (a: ColumnInfo, b: ColumnInfo) => a.name.localeCompare(b.name);

/** Every table a schema module exports, found by what it is rather than listed by hand. */
export const tablesOf = (schemaModule: Record<string, unknown>): ReadonlyArray<SQLiteTable> =>
  Object.values(schemaModule).filter((value): value is SQLiteTable => is(value, SQLiteTable));

/**
 * The columns a Drizzle table declares. drizzle-kit writes a single-column primary key without
 * `NOT NULL`, and `PRAGMA table_info` reports it as nullable, so that key is compared by
 * `primaryKey` alone. Columns of a composite key keep their `NOT NULL`.
 */
export const declaredColumns = (table: SQLiteTable): ReadonlyArray<ColumnInfo> => {
  const composite = getTableConfig(table).primaryKeys.flatMap((key) => key.columns);
  return Object.values(getTableColumns(table))
    .map((column) => ({
      name: column.name,
      type: column.getSQLType().toUpperCase(),
      notNull: column.notNull && !column.primary,
      primaryKey: column.primary || composite.includes(column),
    }))
    .toSorted(byName);
};

interface TableInfoRow {
  readonly name: string;
  readonly type: string;
  readonly notnull: number;
  readonly pk: number;
}

/** The columns the database has, from the rows of `PRAGMA table_info`. */
export const appliedColumns = (rows: ReadonlyArray<TableInfoRow>): ReadonlyArray<ColumnInfo> =>
  rows
    .map((row) => ({
      name: row.name,
      type: row.type.toUpperCase(),
      notNull: row.notnull === 1,
      primaryKey: row.pk > 0,
    }))
    .toSorted(byName);

/** Tables the engine and the migrators keep for themselves. */
export const isBookkeeping = (name: string) =>
  name.startsWith("sqlite_") || name.startsWith("_cf_") || name.startsWith("__");

export { getTableName };
