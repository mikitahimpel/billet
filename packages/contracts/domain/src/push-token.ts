import { Schema } from "effect";

/** `liveactivity` is the push-to-start token (iOS 17.2+). At most one token of each per device. */
export const PushTokenKind = Schema.Literals(["alert", "widget", "liveactivity"]);
export type PushTokenKind = typeof PushTokenKind.Type;

/** Debug builds get sandbox tokens. */
export const ApnsEnvironment = Schema.Literals(["sandbox", "production"]);
export type ApnsEnvironment = typeof ApnsEnvironment.Type;

/** Hex, as APNs issues it. Apple warns the length can change, so only a generous cap applies. */
export const PushToken = Schema.String.check(Schema.isPattern(/^(?:[0-9A-Fa-f]{2}){1,256}$/)).pipe(
  Schema.brand("PushToken"),
);
export type PushToken = typeof PushToken.Type;
