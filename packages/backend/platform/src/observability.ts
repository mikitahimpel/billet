import { routes } from "@billet/contracts-http-api/routes";
import { socketRoute } from "@billet/contracts-realtime/socket-route";

/**
 * Structured log lines for the Worker. One JSON object per line, which Workers Logs indexes by
 * field. They name the route template and never the real path (a media key or a query could hold
 * something personal), and carry no header, body, address or error message.
 */
export const logEvent = (
  level: "log" | "warn" | "error",
  fields: Record<string, unknown>,
): void => {
  console[level](JSON.stringify(fields));
};

const templates: ReadonlyArray<{ readonly method: string; readonly path: string }> = [
  ...Object.values(routes),
  { method: socketRoute.method, path: socketRoute.path },
];

/** `GET /v1/media/*` for a media request, `POST /v1/notes` for a note, and so on. */
export const routeLabel = (method: string, pathname: string): string => {
  for (const template of templates) {
    const prefix = template.path.endsWith("*") ? template.path.slice(0, -1) : undefined;
    const matches = prefix === undefined ? template.path === pathname : pathname.startsWith(prefix);
    if (matches && template.method === method) return `${template.method} ${template.path}`;
  }
  return "unmatched";
};

/**
 * Runs a request and logs its route template, status and duration. A handler that throws is
 * logged as a crash with the error's class only, and answers 500, so a bug is visible in the logs
 * and does not leak its message to the caller.
 */
export const withRequestLog = async (
  request: Request,
  run: () => Promise<Response>,
): Promise<Response> => {
  const route = routeLabel(request.method, new URL(request.url).pathname);
  const started = Date.now();
  try {
    const response = await run();
    logEvent("log", { event: "request", route, status: response.status, ms: Date.now() - started });
    return response;
  } catch (error) {
    logEvent("error", {
      event: "crash",
      route,
      error: error instanceof Error ? error.name : "unknown",
      ms: Date.now() - started,
    });
    return new Response(null, { status: 500 });
  }
};
