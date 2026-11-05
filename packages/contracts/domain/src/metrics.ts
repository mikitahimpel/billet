import { Schema } from "effect";

/**
 * Events the app may report about itself. A name, and for some a short detail from a closed set or
 * a catalogue id: no note, no image, no text, no time (the server stamps it). Adding a name here is
 * a privacy decision, listed in docs/privacy.md. `clientEventRules` says which detail each takes.
 */
export const ClientEventName = Schema.Literals([
  /** The app came to the front. At most one per launch. */
  "AppOpened",
  /** This phone now has a billet widget. Reported once per widget kind (detail: the kind). */
  "WidgetAdded",
  /** The user watched the opening to the end. */
  "OpeningWatched",
  /** The user skipped the opening. */
  "OpeningSkipped",

  /** The cat was stroked. */
  "CatPetted",
  /** The cat was fed: the day's shared `treat`, or other `food`. */
  "CatFed",
  /** A game with the cat (detail: the toy). */
  "CatPlayed",
  /** The cat was called over. */
  "CatCalled",
  /** The cat did a trick it learned (detail: the trick). */
  "TrickDone",
  /** A cat was chosen in the picker (detail: the cat). */
  "CatChosen",
  /** The cat's temperament was shown to the user (detail: the temperament). */
  "TemperamentShown",

  /** A note was opened, from the `widget` or in the `app`. */
  "NoteOpened",

  /** Decorating the room started. */
  "DecoratingOpened",
  /** A piece was put in the room (detail: the item). */
  "RoomItemPlaced",
  /** A piece in the room was moved (detail: the item). */
  "RoomItemMoved",
  /** A piece was taken out of the room (detail: the item). */
  "RoomItemPutAway",
  /** The room itself was changed: walls, floor, window (detail: what was changed). */
  "RoomCustomised",
  /** One of Nooki's rooms came on screen: the diorama `room` or the `city` (detail: which). */
  "RoomOpened",

  /** The shop was opened. */
  "ShopOpened",
  /** An item was looked at in the shop (detail: the item). */
  "ShopItemViewed",
  /** An item was bought with coins (detail: the item; value: its price in coins). */
  "ShopItemBought",
  /** One of the shop's offers came on screen: the week's bundle, a deal or a bundle (detail: it). */
  "ShopOfferViewed",
  /** A bundle was bought (detail: the bundle; value: its price in coins). */
  "ShopBundleBought",
  /** A purchase was taken back within its few seconds (detail: the item or bundle; value: the
   * coins given back). */
  "ShopPurchaseUndone",
  /** The shop's free gift of the day was taken (detail: `coins` or the item; value: coins). */
  "ShopDailyGiftClaimed",
  /** Something was bought for the partner (detail: the item; value: its price in coins). */
  "ShopGiftSent",

  /** The streak's flame scene was opened. */
  "StreakOpened",
  /** A streak milestone was shown (detail: the milestone). */
  "StreakMilestoneSeen",

  /** A button on the widget was tapped: `pet` or `treat`. */
  "WidgetButtonTapped",

  /** The profile ("Us") was opened. */
  "ProfileOpened",
  /** The app asked the user to sign in with Apple. */
  "SignInPromptShown",
  /** The user answered that prompt: `accepted` or `dismissed`. */
  "SignInPromptAnswered",

  /** An onboarding step came on screen (detail: the step id). */
  "OnboardingStepViewed",
  /** An onboarding step was answered (detail: the step id). Never the answer itself. */
  "OnboardingStepAnswered",
  /** An onboarding step was skipped (detail: the step id). */
  "OnboardingStepSkipped",
  /** Onboarding stopped because the person is under 13. Their age answer is never sent. */
  "AgeGateStopped",

  /** A hint came on screen (detail: the tip id). */
  "TipShown",
  /** A hint was closed with its X (detail: the tip id). */
  "TipDismissed",
  /** The hint's thing was done, or its button tapped (detail: the tip id). */
  "TipAction",
]);
export type ClientEventName = typeof ClientEventName.Type;

/**
 * A catalogue id from the app: a cat, a toy, a trick, an item, a temperament. Letters, digits and
 * hyphens, starting with a letter, at most 40. An id names a thing the app ships, never a person.
 */
export const EventDetail = Schema.String.check(Schema.isPattern(/^[A-Za-z][A-Za-z0-9-]{0,39}$/));
export type EventDetail = typeof EventDetail.Type;

/** The most `value` may be. Only a price uses it. */
export const maxEventValue = 100_000;

/**
 * What each name may carry besides itself:
 * - `detail`: absent (`none`), one of a closed list, or a catalogue `id`; `required` when it must
 *   be there;
 * - `value`: a whole number from 0 to `maxEventValue`, only where it says `value: true`.
 */
export interface ClientEventRule {
  readonly detail: "none" | "id" | ReadonlyArray<string>;
  readonly required?: boolean;
  readonly value?: boolean;
}

export const clientEventRules: { readonly [Name in ClientEventName]: ClientEventRule } = {
  AppOpened: { detail: "none" },
  WidgetAdded: { detail: "id" },
  OpeningWatched: { detail: "none" },
  OpeningSkipped: { detail: "none" },
  CatPetted: { detail: "none" },
  CatFed: { detail: ["treat", "food"], required: true },
  CatPlayed: { detail: "id" },
  CatCalled: { detail: "none" },
  TrickDone: { detail: "id", required: true },
  CatChosen: { detail: "id", required: true },
  TemperamentShown: { detail: "id", required: true },
  NoteOpened: { detail: ["widget", "app"], required: true },
  DecoratingOpened: { detail: "none" },
  RoomItemPlaced: { detail: "id", required: true },
  RoomItemMoved: { detail: "id", required: true },
  RoomItemPutAway: { detail: "id", required: true },
  RoomCustomised: { detail: "id" },
  RoomOpened: { detail: ["room", "city"], required: true },
  ShopOpened: { detail: "none" },
  ShopItemViewed: { detail: "id", required: true },
  ShopItemBought: { detail: "id", required: true, value: true },
  ShopOfferViewed: { detail: "id", required: true },
  ShopBundleBought: { detail: "id", required: true, value: true },
  ShopPurchaseUndone: { detail: "id", required: true, value: true },
  ShopDailyGiftClaimed: { detail: "id", required: true, value: true },
  ShopGiftSent: { detail: "id", required: true, value: true },
  StreakOpened: { detail: "none" },
  StreakMilestoneSeen: { detail: "id", required: true },
  WidgetButtonTapped: { detail: ["pet", "treat"], required: true },
  ProfileOpened: { detail: "none" },
  SignInPromptShown: { detail: "none" },
  SignInPromptAnswered: { detail: ["accepted", "dismissed"], required: true },
  OnboardingStepViewed: { detail: "id", required: true },
  OnboardingStepAnswered: { detail: "id", required: true },
  OnboardingStepSkipped: { detail: "id", required: true },
  AgeGateStopped: { detail: "none" },
  TipShown: { detail: "id", required: true },
  TipDismissed: { detail: "id", required: true },
  TipAction: { detail: "id", required: true },
};

/** Why an event breaks its name's rule, or undefined when it keeps it. */
export const clientEventProblem = (event: {
  readonly name: ClientEventName;
  readonly detail?: string | undefined;
  readonly value?: number | undefined;
}): string | undefined => {
  const rule = clientEventRules[event.name];
  if (event.detail === undefined) {
    if (rule.required === true) return `${event.name} needs a detail`;
  } else if (rule.detail === "none") {
    return `${event.name} takes no detail`;
  } else if (rule.detail !== "id" && !rule.detail.includes(event.detail)) {
    return `${event.name} takes one of ${rule.detail.join(", ")}`;
  }
  if (event.value !== undefined && rule.value !== true) return `${event.name} takes no value`;
  return undefined;
};

/** One event with what it carries. The server checks it against `clientEventRules`. */
export const ClientEvent = Schema.Struct({
  name: ClientEventName,
  detail: Schema.optional(EventDetail),
  value: Schema.optional(
    Schema.Int.check(Schema.isGreaterThanOrEqualTo(0), Schema.isLessThanOrEqualTo(maxEventValue)),
  ),
}).check(Schema.makeFilter((event) => clientEventProblem(event) ?? true));
export type ClientEvent = typeof ClientEvent.Type;

/**
 * Events only the server records, from what it already does. `AccountDeleted` is written to
 * Analytics Engine only, since the account's counts go with it.
 */
export const ServerEventName = Schema.Literals([
  "InviteCreated",
  "PairClaimed",
  "NoteSent",
  "AccountDeleted",
]);
export type ServerEventName = typeof ServerEventName.Type;

export const MetricEventName = Schema.Union([ClientEventName, ServerEventName]);
export type MetricEventName = typeof MetricEventName.Type;
