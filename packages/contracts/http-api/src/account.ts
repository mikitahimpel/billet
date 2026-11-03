import { Schema } from "effect";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";

/** Why the caller's partner is gone. The pair ended; the caller keeps the cat. */
export const PartnerLeftReason = Schema.Literals(["account-deleted"]);
export type PartnerLeftReason = typeof PartnerLeftReason.Type;

/** The caller's last pair ended because the partner left, at `at`. */
export const PartnerLeft = Schema.Struct({ reason: PartnerLeftReason, at: EpochMillis });
export type PartnerLeft = typeof PartnerLeft.Type;

/**
 * The caller's account. `linked` is true once it can be recovered with Sign in with Apple.
 * `partnerLeft` is there while the caller is unpaired because their partner left, so the app can
 * say so kindly; `GET /v1/account` is the only response that fills it.
 */
export const AccountResponse = Schema.Struct({
  userId: UserId,
  linked: Schema.Boolean,
  partnerLeft: Schema.optionalKey(PartnerLeft),
});
export type AccountResponse = typeof AccountResponse.Type;

/**
 * An authorization code from a fresh Sign in with Apple, for a linked account: the server trades
 * it for a token and revokes that, as Apple asks of an app that deletes an account. Short-lived and
 * single-use, so it is never stored.
 */
export const AppleAuthorizationCode = Schema.String.check(
  Schema.isNonEmpty(),
  Schema.isMaxLength(1024),
);

export const DeleteAccountRequest = Schema.Struct({
  appleAuthorizationCode: Schema.optionalKey(AppleAuthorizationCode),
});
export type DeleteAccountRequest = typeof DeleteAccountRequest.Type;
