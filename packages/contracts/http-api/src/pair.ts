import { Schema } from "effect";
import { UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";

/** `GET /v1/pair`: the caller's pair and both its members, the caller among them. 404 unpaired. */
export const PairResponse = Schema.Struct({
  pairId: PairId,
  members: Schema.Tuple([UserId, UserId]),
});
export type PairResponse = typeof PairResponse.Type;
