import { Schema } from "effect";
import { DateCatalogResponse } from "@billet/contracts-http-api/dates";
import raw from "./date-catalog.json" with { type: "json" };

/**
 * Every date idea, decoded once when the Worker loads, so a malformed `date-catalog.json` fails
 * the tests and the first request instead of reaching a client. Its `version` is kept current by
 * `scripts/date-catalog-version.mjs`.
 */
export const dateCatalog: DateCatalogResponse = Schema.decodeUnknownSync(DateCatalogResponse)(raw);
