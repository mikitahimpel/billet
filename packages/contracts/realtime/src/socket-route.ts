/** A WebSocket upgrade on the API host (`wss://`), with `Authorization: Bearer <session token>`
 * like the HTTP routes. Frames are `client-message` and `server-message`. */
export const socketRoute = { method: "GET", path: "/v1/socket" } as const;
