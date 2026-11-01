/**
 * The WebSocket of a signed-in device: `GET` with an `Upgrade: websocket` header, at this path on
 * the API host (`wss://`). It authenticates like the HTTP routes, with `Authorization: Bearer
 * <session token>` on the upgrade request. Frames are the messages in `client-message` and
 * `server-message`.
 */
export const socketRoute = { method: "GET", path: "/v1/socket" } as const;
