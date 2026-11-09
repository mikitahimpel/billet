import { Schema } from "effect";
import { UserId } from "@billet/contracts-domain/ids";
import { MoodCheckIn } from "@billet/contracts-domain/mood";
import { PairId } from "@billet/contracts-domain/pair-id";

/** `GET /v1/pair`: 404 unpaired. `moods`: each member's latest check-in, if any. */
export const PairResponse = Schema.Struct({
  pairId: PairId,
  members: Schema.Tuple([UserId, UserId]),
  moods: Schema.Array(MoodCheckIn),
});
export type PairResponse = typeof PairResponse.Type;

/** `GET /v1/dev/demo-partner`, the dev stage only: whether the caller is paired with their bot. */
export const DemoPartnerResponse = Schema.Struct({ paired: Schema.Boolean });
export type DemoPartnerResponse = typeof DemoPartnerResponse.Type;
