import { Schema } from "effect";

export const PairId = Schema.String.check(Schema.isNonEmpty()).pipe(Schema.brand("PairId"));
export type PairId = typeof PairId.Type;
