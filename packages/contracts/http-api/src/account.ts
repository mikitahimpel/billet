import { Schema } from "effect";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";

/** Why the caller's partner is gone. The pair ended, and its cat with it. */
export const PartnerLeftReason = Schema.Literals(["account-deleted"]);
export type PartnerLeftReason = typeof PartnerLeftReason.Type;

export const PartnerLeft = Schema.Struct({ reason: PartnerLeftReason, at: EpochMillis });
export type PartnerLeft = typeof PartnerLeft.Type;

/**
 * `linked`: recoverable with Sign in with Apple. Only `GET /v1/account` fills `partnerLeft`.
 */
export const AccountResponse = Schema.Struct({
  userId: UserId,
  linked: Schema.Boolean,
  partnerLeft: Schema.optionalKey(PartnerLeft),
});
export type AccountResponse = typeof AccountResponse.Type;

/**
 * Traded for a token the server revokes, as Apple requires on account deletion. Never stored.
 */
export const AppleAuthorizationCode = Schema.String.check(
  Schema.isNonEmpty(),
  Schema.isMaxLength(1024),
);

export const DeleteAccountRequest = Schema.Struct({
  appleAuthorizationCode: Schema.optionalKey(AppleAuthorizationCode),
});
export type DeleteAccountRequest = typeof DeleteAccountRequest.Type;
