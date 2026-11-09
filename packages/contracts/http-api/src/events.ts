import { Schema } from "effect";
import { ClientEvent, ClientEventName } from "@billet/contracts-domain/metrics";

/** The most events one request carries. */
export const maxEventsPerRequest = 20;

/** A bare name (older builds) or a `ClientEvent`; the same when there is no detail. */
export const ReportedEvent = Schema.Union([ClientEventName, ClientEvent]);
export type ReportedEvent = typeof ReportedEvent.Type;

/** See `ClientEvent`. The server answers 204. */
export const ReportEventsRequest = Schema.Struct({
  events: Schema.Array(ReportedEvent).check(Schema.isMaxLength(maxEventsPerRequest)),
});
export type ReportEventsRequest = typeof ReportEventsRequest.Type;

/** Either form as a `ClientEvent`. */
export const clientEventOf = (event: ReportedEvent): ClientEvent =>
  typeof event === "string" ? { name: event } : event;
