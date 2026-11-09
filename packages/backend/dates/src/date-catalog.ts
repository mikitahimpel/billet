import { Schema } from "effect";
import { DateCatalogResponse } from "@billet/contracts-http-api/dates";
import raw from "./date-catalog.json" with { type: "json" };

/**
 * Decoded at Worker load, so bad JSON fails tests; `scripts/date-catalog-version.mjs` sets version.
 */
export const dateCatalog: DateCatalogResponse = Schema.decodeUnknownSync(DateCatalogResponse)(raw);
