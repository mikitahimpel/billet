import { routes } from "@billet/contracts-http-api/routes";
import {
  type AppStatus,
  type MaintenanceResponse,
  type StatusResponse,
} from "@billet/contracts-http-api/status";
import { socketRoute } from "@billet/contracts-realtime/socket-route";

const json = (body: unknown, status: number, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...headers },
  });

const reads = new Set(["GET", "HEAD", "OPTIONS"]);

/** Seconds a client should wait before trying a write again: until `until`, within 30 s – 1 h. */
export const retryAfterSeconds = (status: AppStatus, now: number): number => {
  const until = status.maintenance.until === undefined ? NaN : Date.parse(status.maintenance.until);
  if (Number.isNaN(until)) return 300;
  return Math.min(3_600, Math.max(30, Math.ceil((until - now) / 1_000)));
};

/**
 * What the service status decides for a `/v1` request before the API sees it: `/v1/status` itself,
 * or, during maintenance, a 503 for every write and for the realtime socket (which carries writes).
 * `undefined` lets the request through. Nothing here touches the database.
 */
export const gateRequest = (
  request: Request,
  status: AppStatus,
  now: number,
): Response | undefined => {
  const { pathname } = new URL(request.url);
  if (pathname === routes.getStatus.path) {
    if (request.method !== routes.getStatus.method) return json({ error: "method" }, 405);
    return json({ status } satisfies StatusResponse, 200);
  }
  if (!status.maintenance.active) return undefined;
  if (reads.has(request.method) && pathname !== socketRoute.path) return undefined;
  return json({ error: "maintenance", status } satisfies MaintenanceResponse, 503, {
    "retry-after": String(retryAfterSeconds(status, now)),
  });
};
