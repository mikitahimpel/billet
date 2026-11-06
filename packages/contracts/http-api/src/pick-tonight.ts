import { Schema } from "effect";
import { EpochMillis } from "@billet/contracts-domain/ids";
import { ListItemText, TmdbImagePath } from "@billet/contracts-domain/list";
import { PickChoice, PickMatch, PickTitle } from "@billet/contracts-domain/pick-tonight";

/** One of the caller's own swipes in the current session. */
export const PickSwipe = Schema.Struct({ title: PickTitle, choice: PickChoice, at: EpochMillis });
export type PickSwipe = typeof PickSwipe.Type;

/**
 * `GET /v1/pick-tonight`, and the answer to a swipe: the session as the caller sees it. A session is
 * the last 24 hours. `partnerPicked` is how many cards the partner swiped in it; `matches` are the
 * newest first; `match` is present on the answer to the swipe that just made one.
 */
export const PickTonightResponse = Schema.Struct({
  swipes: Schema.Array(PickSwipe),
  partnerPicked: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
  matches: Schema.Array(PickMatch),
  match: Schema.optionalKey(PickMatch),
});
export type PickTonightResponse = typeof PickTonightResponse.Type;

/**
 * `POST /v1/pick-tonight/swipes`: one swipe. Swiping a card again the same way within the session
 * changes nothing; another way replaces the swipe.
 */
export const PickSwipeRequest = Schema.Struct({
  title: PickTitle,
  choice: PickChoice,
  name: ListItemText,
  posterPath: Schema.optionalKey(TmdbImagePath),
});
export type PickSwipeRequest = typeof PickSwipeRequest.Type;
