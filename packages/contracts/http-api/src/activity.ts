import { Schema } from "effect";
import { ActivityCursor, ActivityItem } from "@billet/contracts-domain/activity";

const Unread = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/**
 * One page of the pair's activity, newest first. `next` is absent on the last page; hand it back
 * as `before` for the page after. `unread` is the caller's count of items they have not read.
 */
export const ActivityResponse = Schema.Struct({
  items: Schema.Array(ActivityItem),
  next: Schema.optionalKey(ActivityCursor),
  unread: Unread,
});
export type ActivityResponse = typeof ActivityResponse.Type;

/** Marks every item up to and including `upTo` read for the caller. A mark never moves back. */
export const MarkActivityReadRequest = Schema.Struct({ upTo: ActivityCursor });
export type MarkActivityReadRequest = typeof MarkActivityReadRequest.Type;

export const ActivityUnreadResponse = Schema.Struct({ unread: Unread });
export type ActivityUnreadResponse = typeof ActivityUnreadResponse.Type;
