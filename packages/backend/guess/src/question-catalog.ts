import { Schema } from "effect";
import { GuessCatalogResponse } from "@billet/contracts-http-api/guess";
import raw from "./question-catalog.json" with { type: "json" };

/**
 * Decoded at Worker load, so bad JSON fails tests; `scripts/question-catalog-version.mjs` sets it.
 */
export const questionCatalog: GuessCatalogResponse =
  Schema.decodeUnknownSync(GuessCatalogResponse)(raw);
