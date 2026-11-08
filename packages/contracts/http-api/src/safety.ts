import { Schema } from "effect";

/** Why the caller reports their partner. A closed list, so the admin can count them. */
export const ReportReason = Schema.Literals([
  "harassment",
  "inappropriate",
  "unsafe",
  "spam",
  "other",
]);
export type ReportReason = typeof ReportReason.Type;

/** `POST /v1/pair/report`: reports the caller's current partner. The pair stays as it is. */
export const ReportPartnerRequest = Schema.Struct({
  reason: ReportReason,
  details: Schema.optionalKey(Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(500))),
});
export type ReportPartnerRequest = typeof ReportPartnerRequest.Type;
