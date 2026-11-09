import { routes } from "@billet/contracts-http-api/routes";
import {
  analyticsEnabled,
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

/** Until `until`, clamped to 30 s – 1 h. */
export const retryAfterSeconds = (status: AppStatus, now: number): number => {
  const until = status.maintenance.until === undefined ? NaN : Date.parse(status.maintenance.until);
  if (Number.isNaN(until)) return 300;
  return Math.min(3_600, Math.max(30, Math.ceil((until - now) / 1_000)));
};

/**
 * Maintenance 503s writes and the socket (it carries writes); analytics off drops events (204).
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
  if (
    !analyticsEnabled(status) &&
    pathname === routes.reportEvents.path &&
    request.method === routes.reportEvents.method
  ) {
    return new Response(null, { status: 204 });
  }
  if (!status.maintenance.active) return undefined;
  if (reads.has(request.method) && pathname !== socketRoute.path) return undefined;
  return json({ error: "maintenance", status } satisfies MaintenanceResponse, 503, {
    "retry-after": String(retryAfterSeconds(status, now)),
  });
};
