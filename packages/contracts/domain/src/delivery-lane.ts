import { Schema } from "effect";

/** `LiveActivityPush` is off by default on the server. The order of cases carries no meaning. */
export const DeliveryLane = Schema.TaggedUnion({
  WebSocket: {},
  WidgetPush: {},
  AlertPush: {},
  TimelineRefresh: {},
  LiveActivityPush: {},
});
export type DeliveryLane = typeof DeliveryLane.Type;
