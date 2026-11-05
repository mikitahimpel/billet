import { Schema } from "effect";

/**
 * Which push lane a token serves. `liveactivity` is the device's push-to-start token for the
 * drawing Live Activity (iOS 17.2+). A device holds at most one token of each kind.
 */
export const PushTokenKind = Schema.Literals(["alert", "widget", "liveactivity"]);
export type PushTokenKind = typeof PushTokenKind.Type;

/** The APNs host a token belongs to: debug builds get sandbox tokens. */
export const ApnsEnvironment = Schema.Literals(["sandbox", "production"]);
export type ApnsEnvironment = typeof ApnsEnvironment.Type;

/** Hex, as APNs issues it. Apple warns the length can change, so only a generous cap is enforced. */
export const PushToken = Schema.String.check(Schema.isPattern(/^(?:[0-9A-Fa-f]{2}){1,256}$/)).pipe(
  Schema.brand("PushToken"),
);
export type PushToken = typeof PushToken.Type;
