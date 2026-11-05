import type { InviteCode } from "@billet/contracts-domain/ids";

/**
 * Every HTTP route of the API: method and path. The Worker registers its handlers from this table
 * and a test sends a request to each entry, so a route changed here is served at the new path or
 * fails a test. Clients build their requests from it too.
 */
export interface Route {
  readonly method: "GET" | "POST" | "PUT" | "DELETE";
  readonly path: `/${string}`;
}

const route = <const P extends `/${string}`>(method: Route["method"], path: P) => ({
  method,
  path,
});

export const routes = {
  authChallenge: route("POST", "/v1/auth/challenge"),
  /** Signs in with the account key, opening the account the first time. */
  authAnonymous: route("POST", "/v1/auth/anonymous"),
  /** Signs in to the account linked to this Apple ID, or opens one linked to it. */
  authApple: route("POST", "/v1/auth/apple"),
  /** Links the caller's account to an Apple ID, keeping the user, pair, cat and notes. */
  authAppleLink: route("POST", "/v1/auth/apple/link"),
  authSignOut: route("POST", "/v1/auth/sign-out"),
  getAccount: route("GET", "/v1/account"),
  /** Deletes the caller's account and everything it owns, and ends their pair. */
  deleteAccount: route("DELETE", "/v1/account"),
  registerPushToken: route("PUT", "/v1/devices/current/push-token"),
  createInvite: route("POST", "/v1/invites"),
  claimInvite: route("POST", "/v1/invites/claim"),
  unpair: route("DELETE", "/v1/pair"),
  /** The caller's pair and both members. 404 while the caller has no partner. */
  getPair: route("GET", "/v1/pair"),
  /** Replaces the caller's check-in with how they feel now. */
  setMood: route("PUT", "/v1/mood"),
  uploadImage: route("POST", "/v1/media"),
  /** A media key has slashes in it, so it is the rest of the path: see `mediaPath`. */
  downloadImage: route("GET", "/v1/media/*"),
  /** The app reports a few named events about itself: see `ClientEventName`. */
  reportEvents: route("POST", "/v1/events"),
  /** The experiment variants the caller's pair has been given. */
  getFlags: route("GET", "/v1/flags"),
  /** Maintenance, the minimum build and a notice. No session; answered without the database. */
  getStatus: route("GET", "/v1/status"),
  /** The onboarding questions: see `OnboardingResponse`. Any session, anonymous included. */
  getOnboarding: route("GET", "/v1/onboarding"),
  /** Stores one step's answer or skip, once per account and step. */
  saveOnboardingAnswer: route("POST", "/v1/onboarding/answers"),
  sendNote: route("POST", "/v1/notes"),
  listNotes: route("GET", "/v1/notes"),
  /** Sets or takes back the caller's reaction to one of the partner's photos. */
  react: route("PUT", "/v1/reactions"),
  /** Every reaction change after `after`, oldest first. */
  listReactions: route("GET", "/v1/reactions"),
  /** The couple's cat: its profile, temper and needs now. See docs/cat-state.md. */
  getCat: route("GET", "/v1/cat"),
  /** Adopts the cat the first time, then renames it or changes its look. */
  saveCat: route("PUT", "/v1/cat"),
  /** The cat's journal after `after`, oldest first. */
  listCatJournal: route("GET", "/v1/cat/journal"),
  /** Appends one thing the caller did for the cat, once per `id`. */
  recordCatEvent: route("POST", "/v1/cat/events"),
  /** The pair's recent activity, newest first, for the Inbox. See docs/activity.md. */
  listActivity: route("GET", "/v1/activity"),
  /** Marks the caller's activity read up to a cursor, and answers their unread count. */
  markActivityRead: route("POST", "/v1/activity/read"),
  /** Every ink colour the shop sells, and the ones the pair owns. */
  listInks: route("GET", "/v1/inks"),
  /** The pair's coin balance and wallet entries. */
  getCoins: route("GET", "/v1/coins"),
  /** Buys one item with the pair's coins. */
  buyItem: route("POST", "/v1/shop/buy"),
  /** The pair's balance, inks, room pieces and wishlist. */
  getShop: route("GET", "/v1/shop"),
  /** Buys one offer (an ink, a piece, a set or a treat) with the pair's coins. */
  placeOrder: route("POST", "/v1/shop/orders"),
  /** Adds a piece to the pair's wishlist or takes it off. */
  setWish: route("PUT", "/v1/shop/wishlist"),
  /** Opens the pair's free gift of the local day, once a day for the pair. */
  openGift: route("POST", "/v1/shop/gift"),
  /** Collects a complete collection's coin bonus, once. */
  claimBonus: route("POST", "/v1/shop/bonus"),
  /** Pays something the couple did in the app, once per ref and within the day's caps. */
  earnCoins: route("POST", "/v1/coins/earn"),
  /** The pair's gift wishes, the caller's own gift plans and both partners' "What I love". */
  getGifts: route("GET", "/v1/gifts"),
  /** Makes or changes one of the caller's gift wishes. */
  saveGiftWish: route("PUT", "/v1/gifts/wishes"),
  deleteGiftWish: route("DELETE", "/v1/gifts/wishes"),
  /** Plans, moves on or lets go the caller's secret plan for one of the partner's wishes. */
  setGiftPlan: route("PUT", "/v1/gifts/plans"),
  /** The owner says a wish arrived, or takes that back. */
  markGiftReceived: route("PUT", "/v1/gifts/received"),
  saveLoves: route("PUT", "/v1/gifts/loves"),
  /** Credits a verified App Store transaction's coins to the caller's pair, once. */
  purchase: route("POST", "/v1/purchases"),
  /** The dev stage only: credits or takes back a pack with no App Store. Elsewhere a 404. */
  mockPurchase: route("POST", "/v1/purchases/mock"),
  /** The pair's bought coins: the balance and every ledger entry. */
  getPurchases: route("GET", "/v1/purchases"),
  /** App Store Server Notifications V2 (refunds and the like). Apple calls it; no session. */
  appStoreNotifications: route("POST", "/v1/appstore/notifications"),
} as const satisfies Record<string, Route>;

/**
 * Where an invite link points, on the API's host: a universal link into the app, or a page with
 * the code where the app isn't installed. Outside `/v1/`, as iOS opens it from a browser.
 */
export const inviteLinkPrefix = "/i/";
export const inviteLinkPath = (code: InviteCode): `/i/${string}` => `${inviteLinkPrefix}${code}`;

/** The concrete path of `downloadImage` for a media key. */
export const mediaPath = (key: string): string => routes.downloadImage.path.replace("*", key);

/** How a caller proves who it is, on every route except the sign-in ones. */
export const authorizationHeader = "authorization";
export const bearerPrefix = "Bearer ";

/**
 * What the app says about its own build, on every request. Both are optional: an older build sends
 * neither, and the server reads a missing or malformed value as `unknown`. Nothing in them names a
 * person or a device. `appVersion` is `<marketing version>+<build>`, such as `1.2.0+14`; `os` is the
 * platform and its version, such as `iOS 26.1`.
 */
export const clientHeaders = {
  appVersion: "x-billet-app-version",
  os: "x-billet-os",
} as const;

/**
 * The demo room a caller is in, for the app's demo mode, which has no session and no pair. Only the
 * dev stage reads it, and only on the purchase and coin routes, where it names the ledger
 * (`demo:<code>`) when there is no bearer token. A code is 1 to 64 of `A-Z a-z 0-9 _ -`. Every
 * other stage ignores it.
 */
export const demoRoomHeader = "x-billet-demo-room";
