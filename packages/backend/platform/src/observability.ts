import { type Context, Effect } from "effect";
import type { LogSink, SinkLevel } from "@billet/backend-observability/json-logger";
import { redactField } from "@billet/backend-observability/redact";
import { observabilityLayer } from "@billet/backend-observability/observability-layer";
import { routes } from "@billet/contracts-http-api/routes";
import { socketRoute } from "@billet/contracts-realtime/socket-route";

const templates: ReadonlyArray<{ readonly method: string; readonly path: string }> = [
  ...Object.values(routes),
  { method: socketRoute.method, path: socketRoute.path },
];

/**
 * `GET /v1/media/*` for a media request, `POST /v1/notes` for a note, `GET /admin/*` for the
 * panel (whose paths can hold a pair id), and so on.
 */
export const routeLabel = (method: string, pathname: string): string => {
  for (const template of templates) {
    const prefix = template.path.endsWith("*") ? template.path.slice(0, -1) : undefined;
    const matches = prefix === undefined ? template.path === pathname : pathname.startsWith(prefix);
    if (matches && template.method === method) return `${template.method} ${template.path}`;
  }
  if (pathname === "/admin" || pathname.startsWith("/admin/")) return `${method} /admin/*`;
  return "unmatched";
};

/** The console, split by level so Workers Logs keeps each line's level. */
export const consoleSink: LogSink = (level, line) => {
  switch (level) {
    case "error":
      console.error(line);
      return;
    case "warn":
      console.warn(line);
      return;
    case "debug":
      console.debug(line);
      return;
    case "info":
      console.log(line);
      return;
  }
};

/**
 * One JSON line from code that runs outside Effect, in the logger's shape: `level`, `message` and
 * the fields, each through `redactField`. Prefer `Effect.log*`, which also carries the trace ids.
 */
export const logLine = (
  level: SinkLevel,
  message: string,
  fields: Readonly<Record<string, unknown>> = {},
): void => {
  const line: Record<string, unknown> = { level, message };
  for (const [key, value] of Object.entries(fields)) line[key] = redactField(key, value);
  consoleSink(level, JSON.stringify(line));
};

/**
 * The JSON logger and the span-writing tracer for this isolate (docs/observability.md). One
 * instance, shared by the Worker and the Durable Objects that run in the isolate.
 */
export const Observability = observabilityLayer(consoleSink);

/** Cloudflare's ray id, which the client also sees as the `cf-ray` response header. */
export const requestIdOf = (request: Request): string =>
  request.headers.get("cf-ray") ?? crypto.randomUUID();

/**
 * Runs a request inside an `http.request` root span: method, route template (never the real path:
 * a media key or a query could hold something personal), request id and status. Every log line
 * under it carries `requestId`, `traceId` and `spanId`.
 *
 * `run` receives the context to hand the HTTP router (`handler(request, context)`), so the
 * routes' spans become children of this one and their logs use the JSON logger. A handler that
 * throws is logged once with its redacted cause and answers 500, so a bug shows in the logs
 * without leaking its message to the caller.
 */
export const withRequestSpan = (
  request: Request,
  run: (context: Context.Context<never>) => Promise<Response>,
): Promise<Response> => {
  const requestId = requestIdOf(request);
  return Effect.runPromise(
    Effect.context<never>().pipe(
      Effect.flatMap((context) => Effect.tryPromise(() => run(context))),
      Effect.tap((response) =>
        Effect.annotateCurrentSpan("http.response.status_code", response.status),
      ),
      Effect.tapCause((cause) =>
        Effect.logError("request crashed", cause).pipe(
          Effect.andThen(Effect.annotateCurrentSpan("http.response.status_code", 500)),
        ),
      ),
      Effect.withSpan("http.request", {
        kind: "server",
        root: true,
        attributes: {
          "http.request.method": request.method,
          "http.route": routeLabel(request.method, new URL(request.url).pathname),
          "request.id": requestId,
        },
      }),
      Effect.annotateLogs({ requestId }),
      Effect.catchCause(() => Effect.succeed(new Response(null, { status: 500 }))),
      Effect.provide(Observability),
    ),
  );
};

/**
 * Runs plain async work (a Durable Object call, an alarm) inside a root span named `name`, so it
 * writes a `trace` line like a request does. A throw is logged with its redacted cause and
 * rethrown.
 */
export const traced = <A>(
  name: string,
  attributes: Readonly<Record<string, unknown>>,
  run: (context: Context.Context<never>) => Promise<A>,
): Promise<A> =>
  Effect.runPromise(
    Effect.context<never>().pipe(
      Effect.flatMap((context) =>
        Effect.tryPromise({ try: () => run(context), catch: (error) => error }),
      ),
      Effect.tapCause((cause) => Effect.logError(`${name} failed`, cause)),
      Effect.withSpan(name, { root: true, attributes }),
      Effect.provide(Observability),
    ),
  );
