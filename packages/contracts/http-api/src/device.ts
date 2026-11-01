import { Schema } from "effect";
import { ApnsEnvironment, PushToken, PushTokenKind } from "@billet/contracts-domain/push-token";

/** Registers the signed-in device's token of this kind, replacing any earlier one. */
export const RegisterPushTokenRequest = Schema.Struct({
  kind: PushTokenKind,
  environment: ApnsEnvironment,
  token: PushToken,
});
export type RegisterPushTokenRequest = typeof RegisterPushTokenRequest.Type;
