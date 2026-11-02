import { Schema } from "effect";
import { ClientEventName } from "@billet/contracts-domain/metrics";

/** The most events one request carries. */
export const maxEventsPerRequest = 20;

/** Names only: see `ClientEventName`. The server answers 204. */
export const ReportEventsRequest = Schema.Struct({
  events: Schema.Array(ClientEventName).check(Schema.isMaxLength(maxEventsPerRequest)),
});
export type ReportEventsRequest = typeof ReportEventsRequest.Type;
