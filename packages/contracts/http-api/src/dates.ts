import { Schema } from "effect";
import { DateIdea } from "@billet/contracts-domain/date-ideas";

/** `GET /v1/dates/catalog`. `version` is the ETag, so a client that has it gets a 304. */
export const DateCatalogResponse = Schema.Struct({
  version: Schema.String.check(Schema.isPattern(/^[0-9a-f]{16}$/)),
  ideas: Schema.Array(DateIdea),
});
export type DateCatalogResponse = typeof DateCatalogResponse.Type;
