import { createSelectSchema } from "drizzle-orm/effect-schema";
import type { Table } from "drizzle-orm";
import { Schema } from "effect";

type Fields = Readonly<Record<string, Schema.Top>>;

interface JsonShape {
  readonly type?: string;
  readonly anyOf?: ReadonlyArray<JsonShape>;
}

const kinds = ({ type, anyOf }: JsonShape): ReadonlyArray<string | undefined> =>
  anyOf === undefined ? [type] : anyOf.flatMap(kinds).toSorted();

/** What a column stores: its JSON types. Brands and range checks are the domain's own business. */
const shape = (field: Schema.Top) =>
  kinds(Schema.toJsonSchemaDocument(Schema.toEncoded(field)).schema as JsonShape);

const shapes = (fields: Fields) =>
  Object.fromEntries(
    Object.entries(fields)
      .map(([name, field]) => [name, shape(field)] as const)
      .toSorted(([a], [b]) => a.localeCompare(b)),
  );

/** The column shapes of a table, derived by `drizzle-orm/effect-schema`. */
export const tableShape = (table: Table) => shapes(createSelectSchema(table).fields);

/** The field shapes of a domain struct. */
export const domainShape = (schema: { readonly fields: Fields }) => shapes(schema.fields);
