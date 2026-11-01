import { Schema } from "effect";

/**
 * The four delivery lanes from the architecture. The order of cases carries no meaning:
 * lane order is a decision for #13.
 */
export const DeliveryLane = Schema.TaggedUnion({
  WebSocket: {},
  WidgetPush: {},
  AlertPush: {},
  TimelineRefresh: {},
});
export type DeliveryLane = typeof DeliveryLane.Type;
