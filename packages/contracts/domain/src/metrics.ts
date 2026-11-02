import { Schema } from "effect";

/**
 * Events the app may report about itself. A name and nothing else: no note, no image, no text, no
 * time (the server stamps it). Adding a name here is a privacy decision, listed in docs/privacy.md.
 */
export const ClientEventName = Schema.Literals([
  /** The app came to the front. At most one per launch. */
  "AppOpened",
  /** This phone now has a billet widget on a Home Screen or StandBy. Reported once. */
  "WidgetAdded",
  /** The user watched the opening to the end. */
  "OpeningWatched",
  /** The user skipped the opening. */
  "OpeningSkipped",
]);
export type ClientEventName = typeof ClientEventName.Type;

/** Events only the server records, from what it already does. */
export const ServerEventName = Schema.Literals(["InviteCreated", "PairClaimed", "NoteSent"]);
export type ServerEventName = typeof ServerEventName.Type;

export const MetricEventName = Schema.Union([ClientEventName, ServerEventName]);
export type MetricEventName = typeof MetricEventName.Type;
