import { CODE_HEADER, DEVICE_HEADER, type DemoRoom } from "./demo-room-durable-object.ts";

const ROUTE =
  /^\/demo\/rooms\/([23456789ABCDEFGHJKMNPQRSTVWXYZ]{10})\/(?:socket|notes\/[0-9a-fA-F-]{36})$/;
const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/**
 * Temporary demo route. `rooms` is bound only on the dev stage; without it every demo path is
 * a plain 404, so no other stage exposes it.
 */
export const routeDemo = (
  request: Request,
  rooms: DurableObjectNamespace<DemoRoom> | undefined,
): Promise<Response> | undefined => {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/demo/")) return undefined;
  if (rooms === undefined) return Promise.resolve(new Response(null, { status: 404 }));

  const match = ROUTE.exec(url.pathname);
  const device = url.searchParams.get("device");
  if (request.method !== "GET" || match === null || device === null || !UUID.test(device)) {
    return Promise.resolve(new Response(null, { status: 400 }));
  }
  const headers = new Headers(request.headers);
  headers.set(DEVICE_HEADER, device);
  headers.set(CODE_HEADER, match[1] ?? "");
  return rooms.get(rooms.idFromName(match[1] ?? "")).fetch(new Request(request, { headers }));
};
