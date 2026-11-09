import { Schema } from "effect";
import { EpochMillis } from "@billet/contracts-domain/ids";
import { ListItemText, TmdbImagePath } from "@billet/contracts-domain/list";
import { PickChoice, PickMatch, PickTitle } from "@billet/contracts-domain/pick-tonight";

/** One of the caller's own swipes in the current session. */
export const PickSwipe = Schema.Struct({ title: PickTitle, choice: PickChoice, at: EpochMillis });
export type PickSwipe = typeof PickSwipe.Type;

/**
 * A session is the last 24 hours. `matches` newest first; `match` only on the swipe that made one.
 */
export const PickTonightResponse = Schema.Struct({
  swipes: Schema.Array(PickSwipe),
  partnerPicked: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
  matches: Schema.Array(PickMatch),
  match: Schema.optionalKey(PickMatch),
});
export type PickTonightResponse = typeof PickTonightResponse.Type;

/** `POST /v1/pick-tonight/swipes`: the same way again is a no-op; another way replaces it. */
export const PickSwipeRequest = Schema.Struct({
  title: PickTitle,
  choice: PickChoice,
  name: ListItemText,
  posterPath: Schema.optionalKey(TmdbImagePath),
});
export type PickSwipeRequest = typeof PickSwipeRequest.Type;
