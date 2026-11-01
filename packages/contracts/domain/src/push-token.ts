import { Schema } from "effect";

/**
 * Which push lane a token serves. Live Activity tokens join after the go/no-go in #13.
 * A device holds at most one token of each kind.
 */
export const PushTokenKind = Schema.Literals(["alert", "widget"]);
export type PushTokenKind = typeof PushTokenKind.Type;

/** The APNs host a token belongs to: debug builds get sandbox tokens. */
export const ApnsEnvironment = Schema.Literals(["sandbox", "production"]);
export type ApnsEnvironment = typeof ApnsEnvironment.Type;

/** Hex, as APNs issues it. Apple warns the length can change, so only a generous cap is enforced. */
export const PushToken = Schema.String.check(Schema.isPattern(/^(?:[0-9A-Fa-f]{2}){1,256}$/)).pipe(
  Schema.brand("PushToken"),
);
export type PushToken = typeof PushToken.Type;
