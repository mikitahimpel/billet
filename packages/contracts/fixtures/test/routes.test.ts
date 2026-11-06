import { expect, it } from "vitest";
import { routes } from "@billet/contracts-http-api/routes";
import { socketRoute } from "@billet/contracts-realtime/socket-route";

// Clients copy these. Changing a route means changing this snapshot on purpose, and then the
// iOS client with it.
it("pins the routes that clients call", () => {
  expect({ ...routes, socket: socketRoute }).toMatchInlineSnapshot(`
    {
      "answerGuess": {
        "method": "POST",
        "path": "/v1/guess/answers",
      },
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
      "changeList": {
        "method": "POST",
        "path": "/v1/lists",
      },
      "claimBonus": {
        "method": "POST",
        "path": "/v1/shop/bonus",
      },
      "claimInvite": {
        "method": "POST",
        "path": "/v1/invites/claim",
      },
      "createDemoPartner": {
        "method": "POST",
        "path": "/v1/dev/demo-partner",
      },
      "createInvite": {
        "method": "POST",
        "path": "/v1/invites",
      },
      "deleteAccount": {
        "method": "DELETE",
        "path": "/v1/account",
      },
      "deleteGiftWish": {
        "method": "DELETE",
        "path": "/v1/gifts/wishes",
      },
      "downloadImage": {
        "method": "GET",
        "path": "/v1/media/*",
      },
      "earnCoins": {
        "method": "POST",
        "path": "/v1/coins/earn",
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
      "getDateCatalog": {
        "method": "GET",
        "path": "/v1/dates/catalog",
      },
      "getDemoPartner": {
        "method": "GET",
        "path": "/v1/dev/demo-partner",
      },
      "getFlags": {
        "method": "GET",
        "path": "/v1/flags",
      },
      "getGifts": {
        "method": "GET",
        "path": "/v1/gifts",
      },
      "getGuess": {
        "method": "GET",
        "path": "/v1/guess",
      },
      "getGuessCatalog": {
        "method": "GET",
        "path": "/v1/guess/catalog",
      },
      "getLists": {
        "method": "GET",
        "path": "/v1/lists",
      },
      "getOnboarding": {
        "method": "GET",
        "path": "/v1/onboarding",
      },
      "getPair": {
        "method": "GET",
        "path": "/v1/pair",
      },
      "getPickTonight": {
        "method": "GET",
        "path": "/v1/pick-tonight",
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
      "getTitle": {
        "method": "GET",
        "path": "/v1/titles/:kind/:tmdb",
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
      "listReactions": {
        "method": "GET",
        "path": "/v1/reactions",
      },
      "markActivityRead": {
        "method": "POST",
        "path": "/v1/activity/read",
      },
      "markGiftReceived": {
        "method": "PUT",
        "path": "/v1/gifts/received",
      },
      "mockPurchase": {
        "method": "POST",
        "path": "/v1/purchases/mock",
      },
      "openGift": {
        "method": "POST",
        "path": "/v1/shop/gift",
      },
      "placeOrder": {
        "method": "POST",
        "path": "/v1/shop/orders",
      },
      "purchase": {
        "method": "POST",
        "path": "/v1/purchases",
      },
      "react": {
        "method": "PUT",
        "path": "/v1/reactions",
      },
      "recordCatEvent": {
        "method": "POST",
        "path": "/v1/cat/events",
      },
      "registerPushToken": {
        "method": "PUT",
        "path": "/v1/devices/current/push-token",
      },
      "removeDemoPartner": {
        "method": "DELETE",
        "path": "/v1/dev/demo-partner",
      },
      "reportEvents": {
        "method": "POST",
        "path": "/v1/events",
      },
      "saveCat": {
        "method": "PUT",
        "path": "/v1/cat",
      },
      "saveGiftWish": {
        "method": "PUT",
        "path": "/v1/gifts/wishes",
      },
      "saveLoves": {
        "method": "PUT",
        "path": "/v1/gifts/loves",
      },
      "saveOnboardingAnswer": {
        "method": "POST",
        "path": "/v1/onboarding/answers",
      },
      "searchTitles": {
        "method": "GET",
        "path": "/v1/titles/search",
      },
      "sendNote": {
        "method": "POST",
        "path": "/v1/notes",
      },
      "setGiftPlan": {
        "method": "PUT",
        "path": "/v1/gifts/plans",
      },
      "setMood": {
        "method": "PUT",
        "path": "/v1/mood",
      },
      "setWish": {
        "method": "PUT",
        "path": "/v1/shop/wishlist",
      },
      "socket": {
        "method": "GET",
        "path": "/v1/socket",
      },
      "swipePickTonight": {
        "method": "POST",
        "path": "/v1/pick-tonight/swipes",
      },
      "titleRecommendations": {
        "method": "GET",
        "path": "/v1/titles/recommendations",
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
