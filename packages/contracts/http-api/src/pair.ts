import { Schema } from "effect";
import { UserId } from "@billet/contracts-domain/ids";
import { MoodCheckIn } from "@billet/contracts-domain/mood";
import { PairId } from "@billet/contracts-domain/pair-id";

/**
 * `GET /v1/pair`: the caller's pair and both its members, the caller among them. 404 unpaired.
 * `moods` holds each member's latest check-in, for those who have checked in.
 */
export const PairResponse = Schema.Struct({
  pairId: PairId,
  members: Schema.Tuple([UserId, UserId]),
  moods: Schema.Array(MoodCheckIn),
});
export type PairResponse = typeof PairResponse.Type;
