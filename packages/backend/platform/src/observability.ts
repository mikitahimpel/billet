import { type Context, Effect } from "effect";
import { HttpMiddleware } from "effect/http";
import type { LogSink, SinkLevel } from "@billet/backend-observability/json-logger";
import { redactField } from "@billet/backend-observability/redact";
import { observabilityLayer } from "@billet/backend-observability/observability-layer";
import { routes } from "@billet/contracts-http-api/routes";
import { socketRoute } from "@billet/contracts-realtime/socket-route";

const templates: ReadonlyArray<{ readonly method: string; readonly path: string }> = [
  ...Object.values(routes),
  { method: socketRoute.method, path: socketRoute.path },
];

/** Templates the path (for example `GET /v1/media/*`); admin paths can hold a pair id. */
export const routeLabel = (method: string, pathname: string): string => {
  for (const template of templates) {
    const prefix = template.path.endsWith("*") ? template.path.slice(0, -1) : undefined;
    const matches = prefix === undefined ? template.path === pathname : pathname.startsWith(prefix);
    if (matches && template.method === method) return `${template.method} ${template.path}`;
  }
  if (pathname === "/admin" || pathname.startsWith("/admin/")) return `${method} /admin/*`;
  return "unmatched";
};

/** Split by level so Workers Logs keeps each line's level. */
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

/** For code outside Effect; prefer `Effect.log*`, which also carries the trace ids. */
export const logLine = (
  level: SinkLevel,
  message: string,
  fields: Readonly<Record<string, unknown>> = {},
): void => {
  const line: Record<string, unknown> = { level, message };
  for (const [key, value] of Object.entries(fields)) line[key] = redactField(key, value);
  consoleSink(level, JSON.stringify(line));
};

/** Shared by the Worker and the Durable Objects in the isolate (docs/observability.md). */
export const Observability = observabilityLayer(consoleSink);

/** Cloudflare's ray id; otherwise 16 random hex digits, short enough not to look like a token. */
export const requestIdOf = (request: Request): string =>
  request.headers.get("cf-ray") ?? crypto.randomUUID().replaceAll("-", "").slice(0, 16);

/** Spans carry the route template, never the real path; a throw answers 500 without leaking. */
export const withRequestSpan = (
  request: Request,
  run: (context: Context.Context<never>) => Promise<Response>,
): Promise<Response> => {
  const requestId = requestIdOf(request);
  const route = routeLabel(request.method, new URL(request.url).pathname);
  return Effect.runPromise(
    Effect.context<never>().pipe(
      Effect.flatMap((context) => Effect.tryPromise(() => run(context))),
      // The router would open its own server span carrying the raw URL.
      Effect.provideService(HttpMiddleware.TracerDisabledWhen, () => true),
      // The router sets `http.route` to its path template; the label adds the method.
      Effect.tap((response) =>
        Effect.annotateCurrentSpan({
          "http.route": route,
          "http.response.status_code": response.status,
        }),
      ),
      Effect.tapCause((cause) =>
        Effect.logError("request crashed", cause).pipe(
          Effect.andThen(
            Effect.annotateCurrentSpan({ "http.route": route, "http.response.status_code": 500 }),
          ),
        ),
      ),
      Effect.withSpan("http.request", {
        kind: "server",
        root: true,
        attributes: {
          "http.request.method": request.method,
          "http.route": route,
          "request.id": requestId,
        },
      }),
      Effect.annotateLogs({ requestId }),
      Effect.catchCause(() => Effect.succeed(new Response(null, { status: 500 }))),
      Effect.provide(Observability),
    ),
  );
};

/** A throw is logged with its redacted cause and rethrown. */
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
