import { Schema } from "effect";

/** Never a note, image, text or time (the server stamps it). Adding a name is a privacy
 * decision, listed in docs/privacy.md. */
export const ClientEventName = Schema.Literals([
  /** At most one per launch. */
  "AppOpened",
  /** Reported once per widget kind. */
  "WidgetAdded",
  "OpeningWatched",
  "OpeningSkipped",

  "CatPetted",
  /** `treat` is the day's shared one. */
  "CatFed",
  "CatPlayed",
  "CatCalled",
  "TrickDone",
  "CatChosen",
  "TemperamentShown",

  "NoteOpened",

  "DecoratingOpened",
  "RoomItemPlaced",
  "RoomItemMoved",
  "RoomItemPutAway",
  /** Walls, floor or window. */
  "RoomCustomised",
  "RoomOpened",

  "ShopOpened",
  "ShopItemViewed",
  /** value: the price in coins. */
  "ShopItemBought",
  "ShopOfferViewed",
  /** value: the price in coins. */
  "ShopBundleBought",
  /** value: the coins given back. */
  "ShopPurchaseUndone",
  /** detail: `coins` or the item; value: coins. */
  "ShopDailyGiftClaimed",
  /** value: the price in coins. */
  "ShopGiftSent",

  "StreakOpened",
  "StreakMilestoneSeen",

  "WidgetButtonTapped",

  /** One session. */
  "PickTonightOpened",
  "PickTonightMatched",
  "PickTonightPlanned",

  "ProfileOpened",
  "SignInPromptShown",
  "SignInPromptAnswered",

  "OnboardingStepViewed",
  /** Never the answer itself. */
  "OnboardingStepAnswered",
  "OnboardingStepSkipped",
  /** Under 13. The age answer is never sent. */
  "AgeGateStopped",

  "TipShown",
  "TipDismissed",
  "TipAction",
]);
export type ClientEventName = typeof ClientEventName.Type;

/** A catalogue id the app ships (cat, toy, item…), never a person. */
export const EventDetail = Schema.String.check(Schema.isPattern(/^[A-Za-z][A-Za-z0-9-]{0,39}$/));
export type EventDetail = typeof EventDetail.Type;

export const maxEventValue = 100_000;

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
  PickTonightOpened: { detail: "none" },
  PickTonightMatched: { detail: "none" },
  PickTonightPlanned: { detail: "none" },
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

/** Undefined when the event keeps its name's rule. */
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

export const ClientEvent = Schema.Struct({
  name: ClientEventName,
  detail: Schema.optional(EventDetail),
  value: Schema.optional(
    Schema.Int.check(Schema.isGreaterThanOrEqualTo(0), Schema.isLessThanOrEqualTo(maxEventValue)),
  ),
}).check(Schema.makeFilter((event) => clientEventProblem(event) ?? true));
export type ClientEvent = typeof ClientEvent.Type;

/** `AccountDeleted` goes to Analytics Engine only, since the account's counts go with it.
 * `DemoPairClaimed` (a dev-stage demo partner) stays in pair history, out of the funnel. */
export const ServerEventName = Schema.Literals([
  "InviteCreated",
  "PairClaimed",
  "DemoPairClaimed",
  "NoteSent",
  "AccountDeleted",
]);
export type ServerEventName = typeof ServerEventName.Type;

export const MetricEventName = Schema.Union([ClientEventName, ServerEventName]);
export type MetricEventName = typeof MetricEventName.Type;
