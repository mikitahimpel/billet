import { expect, it } from "vitest";
import { routes } from "@billet/contracts-http-api/routes";
import { socketRoute } from "@billet/contracts-realtime/socket-route";

// Clients copy these. Changing a route means changing this snapshot on purpose, and then the
// iOS client with it.
it("pins the routes that clients call", () => {
  expect({ ...routes, socket: socketRoute }).toMatchInlineSnapshot(`
    {
      "appStoreNotifications": {
        "method": "POST",
        "path": "/v1/appstore/notifications",
      },
      "authAnonymous": {
        "method": "POST",
        "path": "/v1/auth/anonymous",
      },
      "authApple": {
        "method": "POST",
        "path": "/v1/auth/apple",
      },
      "authAppleLink": {
        "method": "POST",
        "path": "/v1/auth/apple/link",
      },
      "authChallenge": {
        "method": "POST",
        "path": "/v1/auth/challenge",
      },
      "authSignOut": {
        "method": "POST",
        "path": "/v1/auth/sign-out",
      },
      "buyItem": {
        "method": "POST",
        "path": "/v1/shop/buy",
      },
      "claimInvite": {
        "method": "POST",
        "path": "/v1/invites/claim",
      },
      "createInvite": {
        "method": "POST",
        "path": "/v1/invites",
      },
      "deleteAccount": {
        "method": "DELETE",
        "path": "/v1/account",
      },
      "downloadImage": {
        "method": "GET",
        "path": "/v1/media/*",
      },
      "getAccount": {
        "method": "GET",
        "path": "/v1/account",
      },
      "getCat": {
        "method": "GET",
        "path": "/v1/cat",
      },
      "getCoins": {
        "method": "GET",
        "path": "/v1/coins",
      },
      "getFlags": {
        "method": "GET",
        "path": "/v1/flags",
      },
      "getOnboarding": {
        "method": "GET",
        "path": "/v1/onboarding",
      },
      "getPair": {
        "method": "GET",
        "path": "/v1/pair",
      },
      "getPurchases": {
        "method": "GET",
        "path": "/v1/purchases",
      },
      "getShop": {
        "method": "GET",
        "path": "/v1/shop",
      },
      "getStatus": {
        "method": "GET",
        "path": "/v1/status",
      },
      "listActivity": {
        "method": "GET",
        "path": "/v1/activity",
      },
      "listCatJournal": {
        "method": "GET",
        "path": "/v1/cat/journal",
      },
      "listInks": {
        "method": "GET",
        "path": "/v1/inks",
      },
      "listNotes": {
        "method": "GET",
        "path": "/v1/notes",
      },
      "markActivityRead": {
        "method": "POST",
        "path": "/v1/activity/read",
      },
      "mockPurchase": {
        "method": "POST",
        "path": "/v1/purchases/mock",
      },
      "placeOrder": {
        "method": "POST",
        "path": "/v1/shop/orders",
      },
      "purchase": {
        "method": "POST",
        "path": "/v1/purchases",
      },
      "recordCatEvent": {
        "method": "POST",
        "path": "/v1/cat/events",
      },
      "registerPushToken": {
        "method": "PUT",
        "path": "/v1/devices/current/push-token",
      },
      "reportEvents": {
        "method": "POST",
        "path": "/v1/events",
      },
      "saveCat": {
        "method": "PUT",
        "path": "/v1/cat",
      },
      "saveOnboardingAnswer": {
        "method": "POST",
        "path": "/v1/onboarding/answers",
      },
      "sendNote": {
        "method": "POST",
        "path": "/v1/notes",
      },
      "setWish": {
        "method": "PUT",
        "path": "/v1/shop/wishlist",
      },
      "socket": {
        "method": "GET",
        "path": "/v1/socket",
      },
      "unpair": {
        "method": "DELETE",
        "path": "/v1/pair",
      },
      "uploadImage": {
        "method": "POST",
        "path": "/v1/media",
      },
    }
  `);
});
