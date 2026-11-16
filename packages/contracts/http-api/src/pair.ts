import { Schema } from "effect";
import { LocalDay } from "@billet/contracts-domain/coins";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { MoodCheckIn } from "@billet/contracts-domain/mood";
import { PairId } from "@billet/contracts-domain/pair-id";

/** Unicode scalars, the same count Swift's `DisplayName` makes. */
export const displayNameMaxScalars = 40;

const controlCharacter = /\p{Cc}/u;

/** What a partner calls themselves in the app. Trimmed, never empty. */
export const DisplayName = Schema.String.check(
  Schema.makeFilter(
    (name) =>
      (name.length > 0 &&
        name === name.trim() &&
        [...name].length <= displayNameMaxScalars &&
        !controlCharacter.test(name)) ||
      `expected a trimmed name of 1 to ${displayNameMaxScalars} characters, without control characters`,
  ),
).pipe(Schema.brand("DisplayName"));
export type DisplayName = typeof DisplayName.Type;

export const MemberName = Schema.Struct({ userId: UserId, displayName: DisplayName });
export type MemberName = typeof MemberName.Type;

/**
 * `GET /v1/pair`: 404 unpaired. `moods`: each member's latest check-in, if any. `names`: the
 * members who set one. `togetherSince`: the pair's day once a partner set it; until then the pair
 * counts from `pairedAt`, the moment its invite was claimed. Older servers send none of the three.
 */
export const PairResponse = Schema.Struct({
  pairId: PairId,
  members: Schema.Tuple([UserId, UserId]),
  moods: Schema.Array(MoodCheckIn),
  names: Schema.optionalKey(Schema.Array(MemberName)),
  togetherSince: Schema.optionalKey(LocalDay),
  pairedAt: Schema.optionalKey(EpochMillis),
});
export type PairResponse = typeof PairResponse.Type;

/** `PUT /v1/me`: `null` forgets the caller's name. Works paired or not; answers 204. */
export const SetDisplayNameRequest = Schema.Struct({ displayName: Schema.NullOr(DisplayName) });
export type SetDisplayNameRequest = typeof SetDisplayNameRequest.Type;

/**
 * `PUT /v1/pair/together-since`: either partner sets the pair's day; 404 unpaired, else 204.
 * `ifUnset`: only when no one has set it yet, as a phone does with the day chosen before pairing.
 */
export const SetTogetherSinceRequest = Schema.Struct({
  day: LocalDay,
  ifUnset: Schema.optionalKey(Schema.Boolean),
});
export type SetTogetherSinceRequest = typeof SetTogetherSinceRequest.Type;

/** `GET /v1/dev/demo-partner`, the dev stage only: whether the caller is paired with their bot. */
export const DemoPartnerResponse = Schema.Struct({ paired: Schema.Boolean });
export type DemoPartnerResponse = typeof DemoPartnerResponse.Type;
