import { Schema } from "effect";

/**
 * The delivery lanes from the architecture, plus the Live Activity a drawing starts on the
 * partner's lock screen (off by default on the server). The order of cases carries no meaning.
 */
export const DeliveryLane = Schema.TaggedUnion({
  WebSocket: {},
  WidgetPush: {},
  AlertPush: {},
  TimelineRefresh: {},
  LiveActivityPush: {},
});
export type DeliveryLane = typeof DeliveryLane.Type;
