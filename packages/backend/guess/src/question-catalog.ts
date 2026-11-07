import { Schema } from "effect";
import { GuessCatalogResponse } from "@billet/contracts-http-api/guess";
import raw from "./question-catalog.json" with { type: "json" };

/**
 * Every Who knows who question, decoded once when the Worker loads, so a malformed
 * `question-catalog.json` fails the tests and the first request instead of reaching a client. Its
 * `version` is kept current by `scripts/question-catalog-version.mjs`.
 */
export const questionCatalog: GuessCatalogResponse =
  Schema.decodeUnknownSync(GuessCatalogResponse)(raw);
