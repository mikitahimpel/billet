# Observability

The `Api` Worker and its Durable Objects write one JSON object per log line. Cloudflare Workers
Logs keeps them and indexes every field, so a request, a trace or a pair can be found by field in
the dashboard. Effect spans go into the same logs: each request writes one `trace` line holding its
spans. Nothing here needs a paid vendor.

- `packages/backend/observability`: the JSON logger, the tracer that writes spans as log lines, the
  redaction rules and `opaqueRef`. Pure Effect, tested without `workerd`.
- `packages/backend/platform/src/observability.ts`: wires them to the console, and holds the
  request span (`withRequestSpan`) and the root span for plain async work (`traced`).
- `alchemy.run.ts`: turns on Workers Logs and Workers traces for the `Api` Worker, with sampling.

## What a line looks like

A log line from `Effect.log*`:

```json
{
  "level": "error",
  "message": "notes unavailable",
  "data": { "name": "NotesUnavailable", "_tag": "NotesUnavailable", "reason": "room-unavailable", "cause": { "name": "TypeError", "stack": ["at …"] } },
  "traceId": "4bf92f3577b34da6a3ce929d0e0e4736",
  "spanId": "00f067aa0ba902b7",
  "span": "PairRooms.sendNote",
  "requestId": "8d2f0a1b2c3d4e5f-LHR"
}
```

- `level`: `debug`, `info`, `warn` or `error`. The line goes to the matching `console` method, so
  Workers Logs shows the same level.
- `message`: a fixed label. Further message parts go under `data`.
- `traceId`, `spanId`, `span`: the span the line was written in.
- `requestId` and any other log annotation, as top-level fields.
- `cause`: for a failure, a short list of `{ kind, error }`. `kind` is `fail`, `defect` or
  `interrupt`.

A `trace` line, written when a root span ends:

```json
{
  "level": "info",
  "message": "trace",
  "traceId": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span": "http.request",
  "spanId": "a3ce929d0e0e4736",
  "ms": 41.2,
  "status": "ok",
  "attributes": {
    "http.request.method": "POST",
    "http.route": "POST /v1/notes",
    "http.response.status_code": 200,
    "request.id": "8d2f0a1b2c3d4e5f-LHR",
    "user.ref": "f84ba2aa754a4bd4",
    "pair.ref": "0c1d9a6e3b2f4471"
  },
  "spans": [
    { "name": "AuthEngine.findSession", "spanId": "…", "parentId": "…", "ms": 3, "status": "ok" },
    { "name": "AuthService.authenticate", "spanId": "…", "parentId": "a3ce929d0e0e4736", "ms": 4, "status": "ok" },
    { "name": "PairRooms.sendNote", "spanId": "…", "parentId": "…", "ms": 30.5, "status": "error", "error": "NotesUnavailable" },
    { "name": "NotesService.sendNote", "spanId": "…", "parentId": "a3ce929d0e0e4736", "ms": 36, "status": "error", "error": "NotesUnavailable" }
  ]
}
```

## Root spans

| Root span | Where | Written for |
| --- | --- | --- |
| `http.request` | `withRequestSpan`, every `/v1/` and `/admin` request | method, route template, status, `request.id`, `user.ref`, `pair.ref` |
| `PairRoom.open`, `.sendNote`, `.notes`, `.setPresence`, `.forgetMember` | `PairRoom.run` | each room command; reads made per drawing frame are not traced |
| `PairRoom.alarm` | `PairRoom.alarm` | one line per alarm, plus a `delivery` line per try |
| `DemoRoom.fetch`, `.note`, `.play`, `.alarm`, `.alertPartner` | the demo room (`demo-trace.ts`) | requests, notes, plays (with `play.kind`), the evening reminder, APNs alerts. The demo Worker must not load Effect, so these lines are written by hand in the same shape, with no child spans |

A Durable Object call is its own trace: the Worker's `PairRooms.sendNote` span and the room's
`PairRoom.sendNote` trace are joined by `pair.ref` and time. Cloudflare's own Workers traces
(below) do link the Worker's call to the Durable Object.

## Child spans

- Services name their methods with `Effect.fn("Service.method")`: `AuthService.*`,
  `NotesService.*`, `PairingService.*`, `PaymentsService.*`, `AccountDeletion.*`,
  `FlagsService.flagsFor`.
- Repositories and adapters built as object literals are wrapped with `spanMethods("Name", …)`:
  `AuthRepository`, `AuthEngine`, `AccountRepository`, `AccountNotices`, `PairingRepository`,
  `PairingObserver`, `PaymentsRepository`, `FlagsRepository`, `FlagConfigRepository`, `MetricsRepository`,
  `AdminData`, `MediaStore`, `PairRooms`, `EventSink` (analytics events), `AppleTokenRevoker`.
- `@effect/sql` adds a `sqlite` or `BATCH` span per statement, and `HttpClient` a `GET`/`POST` span per outbound call (Apple's keys). The SQL text and any `url.full`/`url.path`/`url.query` are left out of the line. The HTTP router's own server span is switched off: `http.request` replaces it.
- `Effect.fnUntraced` stays only on inner helpers that run many times per request
  (`FlagsService.decide`, `AuthService.liveSession`, `issued` in the auth engine).

New code follows the same pattern: `Effect.fn("Service.method")` for a service, `spanMethods` for
an adapter, and `annotateRefs({ user, pair })` where a request first learns who it is about.

## Errors

A typed failure (`NotesUnavailable`, `AuthUnavailable`, …) is logged once, at the edge: the route's
error handler logs the error itself, with its `reason` and the `cause` underneath, and answers
503. The error's `message` is never logged, only its class, tag, fields and stack frames.
`AuthRejected` is logged at `info`, other client errors (400, 404, 409) are not logged.

A defect (a bug, a throw) that reaches the HTTP server is logged by the error reporter as
`unhandled failure`. A throw outside Effect ends the request span as `request crashed` and answers
500. Either way the line carries the trace and request ids.

## What never reaches a log

`redact` (packages/backend/observability/src/redact.ts) runs on every message part, annotation and
span attribute:

- a `Redacted` value is `<redacted>`;
- a field whose name contains `token`, `secret`, `password`, `authorization`, `cookie`, `session`,
  `email`, `phone`, `body`, `text`, `content`, `key`, `signature`, `credential` or `stroke` is
  `<redacted>`;
- a string that looks like an email, or like a token (32 or more token characters in one run), is
  `<redacted>`;
- an error loses its message, which can quote the input;
- anything deeper than four levels, longer than 30 entries or 200 characters is cut.

The request span names the route template, never the path, and no header. User and pair ids are
written only as `opaqueRef`s: 16 hex digits of FNV-1a 64 of the id. `test/observability.test.ts`
in both packages checks that a fake token, JWT and email never come out.

## Find a request by ID

Every Cloudflare response carries a `cf-ray` header, and the request span stores it as
`request.id` (and every log line as `requestId`).

1. Get the ray id: from the app's network log, or from the response headers (`cf-ray: 8d2f…-LHR`).
2. Cloudflare dashboard → Workers & Pages → the stage's `Api` Worker → Observability → Events.
3. Filter `requestId = 8d2f…-LHR` for the request's log lines, or
   `attributes.request.id = 8d2f…-LHR` for its `trace` line. Take its `traceId` and filter
   `traceId = …` to see every line of that request.

To find a user's or a pair's lines, compute the ref of their id and filter `attributes.user.ref`
or `attributes.pair.ref`:

```sh
node -e 'let h=0xcbf29ce484222325n;for(const b of new TextEncoder().encode(process.argv[1]))h=((h^BigInt(b))*0x100000001b3n)&0xffffffffffffffffn;console.log(h.toString(16).padStart(16,"0"))' <pair-id>
```

Other useful filters: `level = error` (all errors), `message = trace AND status = error` (failed
requests), `span = http.request AND ms > 500` (slow requests), `event = delivery` (delivery tries).

## Read a trace

A `trace` line is one request. `ms` and `status` at the top are the whole request. Each entry in
`spans` is one child span, in the order it ended, so the innermost work comes first. `parentId`
points to its parent: the root's `spanId`, or another entry's. The first entry with
`status: error` and the deepest `parentId` chain is usually where it failed; its `error` is the tag
of the failure. Log lines with the same `spanId` were written inside that span.

Durations come from the Worker's clock, which does not move while code runs on the CPU (a Workers
security rule), so `ms` measures time spent waiting on I/O (D1, R2, the Durable Object, Apple), not
CPU time. CPU time per request is in the Worker's metrics.

A child span that ends after its root, such as forked follow-up work, gets a `span` line of its
own with the same `traceId`. A trace keeps at most 100 child spans and counts the rest in
`droppedSpans`.

## Sampling

Set in `alchemy.run.ts`, for the `Api` Worker:

| Stage | Head sampling | How |
| --- | --- | --- |
| `dev` | 100% | default |
| `prod` | 15% (planned) | default; `API_SAMPLING_RATE=0.1` for one deploy |

Head sampling picks whole requests: a kept request keeps all its log lines, its `trace` line and
its Workers trace, and a dropped one keeps none. Logs and traces are persisted, and query strings
are redacted by Cloudflare as well. Workers Logs keeps lines for 7 days on the paid plan, with
20 million lines a month included. At 15% the prod volume is a small part of that.

Cloudflare's own Workers traces are on too. They show the platform's view of each invocation
(fetch, D1, R2, KV and Durable Object calls, with timings), in the dashboard under Observability →
Traces. They cannot carry Effect's spans, which is why those go into the logs.

## Recent errors in the admin panel

Not built yet: it needs a token the Worker could use to query its own logs, and none exists. The
only Cloudflare token is the deploy token, which must not be bound into the Worker. The owner would
need to:

1. Create an account API token with only the Workers Observability read permission (Account →
   Workers Observability → Read), for the billet account.
2. Store it in Proton Pass ("Billet/Cloudflare Observability", field `token`) and add
   `OBSERVABILITY_API_TOKEN=pass://Billet/Cloudflare Observability/token` to `.env.pass`.

Then the panel can add a Recent errors view: the Worker binds the token as a `Config.Redacted`
secret and calls the Workers Observability telemetry query API
(`POST /accounts/{account_id}/workers/observability/telemetry/query`) with `level = error` over the
last 24 hours, showing message, `span`, `requestId` and time. Until then, the dashboard filter
`level = error` gives the same list.

## Later: an external backend

Not worth it yet. Two people use billet, Workers Logs is included in the plan, and a `trace` line
answers what a span backend would. If the traffic or the questions grow (latency percentiles per
span, long retention), Workers Observability can export logs and traces over OTLP to a destination
(`observability.logs.destinations` / `traces.destinations` in `alchemy.run.ts`), and Effect's own
`OtlpTracer` (`effect/observability`) could replace the trace-log tracer. Self-hosted or free-tier
backends (Grafana Cloud free, a self-hosted Jaeger or SigNoz) would do; no paid vendor is planned.
