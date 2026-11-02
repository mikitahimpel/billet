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
  authApple: route("POST", "/v1/auth/apple"),
  authSignOut: route("POST", "/v1/auth/sign-out"),
  registerPushToken: route("PUT", "/v1/devices/current/push-token"),
  createInvite: route("POST", "/v1/invites"),
  claimInvite: route("POST", "/v1/invites/claim"),
  unpair: route("DELETE", "/v1/pair"),
  uploadImage: route("POST", "/v1/media"),
  /** A media key has slashes in it, so it is the rest of the path: see `mediaPath`. */
  downloadImage: route("GET", "/v1/media/*"),
  /** The app reports a few named events about itself: see `ClientEventName`. */
  reportEvents: route("POST", "/v1/events"),
  /** The experiment variants the caller's pair has been given. */
  getFlags: route("GET", "/v1/flags"),
  sendNote: route("POST", "/v1/notes"),
  listNotes: route("GET", "/v1/notes"),
} as const satisfies Record<string, Route>;

/** The concrete path of `downloadImage` for a media key. */
export const mediaPath = (key: string): string => routes.downloadImage.path.replace("*", key);

/** How a caller proves who it is, on every route except the two sign-in ones. */
export const authorizationHeader = "authorization";
export const bearerPrefix = "Bearer ";
