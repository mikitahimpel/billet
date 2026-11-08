import { Schema } from "effect";
import { NoteId } from "@billet/contracts-domain/ids";

/** Why the caller reports their partner. A closed list, so the admin can count them. */
export const ReportReason = Schema.Literals([
  "harassment",
  "inappropriate",
  "unsafe",
  "spam",
  "other",
]);
export type ReportReason = typeof ReportReason.Type;

/**
 * `POST /v1/pair/report`: reports the caller's current partner. The pair stays as it is. `noteId`
 * names the one note or photo the report is about, when there is one.
 */
export const ReportPartnerRequest = Schema.Struct({
  reason: ReportReason,
  noteId: Schema.optionalKey(NoteId),
  details: Schema.optionalKey(Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(500))),
});
export type ReportPartnerRequest = typeof ReportPartnerRequest.Type;
