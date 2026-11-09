import { Schema } from "effect";
import { Ink, InkId } from "@billet/contracts-domain/inks";

/** `GET /v1/inks`. `owned` holds the free ink first, then the rest in the order bought. */
export const InksResponse = Schema.Struct({
  inks: Schema.Array(Ink),
  owned: Schema.Array(InkId),
});
export type InksResponse = typeof InksResponse.Type;
