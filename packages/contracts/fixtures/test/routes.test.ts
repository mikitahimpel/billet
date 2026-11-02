import { expect, it } from "vitest";
import { routes } from "@billet/contracts-http-api/routes";
import { socketRoute } from "@billet/contracts-realtime/socket-route";

// Clients copy these. Changing a route means changing this snapshot on purpose, and then the
// iOS client with it.
it("pins the routes that clients call", () => {
  expect({ ...routes, socket: socketRoute }).toMatchInlineSnapshot(`
    {
      "authApple": {
        "method": "POST",
        "path": "/v1/auth/apple",
      },
      "authChallenge": {
        "method": "POST",
        "path": "/v1/auth/challenge",
      },
      "authSignOut": {
        "method": "POST",
        "path": "/v1/auth/sign-out",
      },
      "claimInvite": {
        "method": "POST",
        "path": "/v1/invites/claim",
      },
      "createInvite": {
        "method": "POST",
        "path": "/v1/invites",
      },
      "downloadImage": {
        "method": "GET",
        "path": "/v1/media/*",
      },
      "getFlags": {
        "method": "GET",
        "path": "/v1/flags",
      },
      "listNotes": {
        "method": "GET",
        "path": "/v1/notes",
      },
      "registerPushToken": {
        "method": "PUT",
        "path": "/v1/devices/current/push-token",
      },
      "sendNote": {
        "method": "POST",
        "path": "/v1/notes",
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
