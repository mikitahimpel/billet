# Maintenance, minimum build and notice

One small **service status** tells every app, signed in or not, whether billet is under
maintenance, which builds are too old to run, and an optional soft notice. The owner sets it in the
admin panel (Maintenance). It is built to keep working when the database or the rest of the API is
broken.

## The status

`AppStatus` (`packages/contracts/http-api/src/status.ts`):

| Field | Meaning |
| --- | --- |
| `maintenance.active` | billet is under maintenance: the server refuses every write, the app shows a calm maintenance screen |
| `maintenance.message` | `{ key, text }`: a localized string the app may carry (`key`), and the text it shows otherwise |
| `maintenance.until` | optional UTC time, for "back around HH:MM". A hint only: maintenance ends when the owner switches it off |
| `minVersion` | optional `<marketing>` or `<marketing>+<build>` (`1.2.0+14`), ordered like experiment targeting. An older build shows "Update billet" and nothing else |
| `notice` | optional `{ key, text }`, a dismissible banner such as "Notes may be slow tonight" |

The app gets it three ways:

- `GET /v1/status`: no session, never touches D1. The app reads it at launch, on foreground and
  about every minute while open, in both the demo and the real build.
- `status` next to `flags` in `GET /v1/flags`.
- the body of the 503 every write gets during maintenance (below).

Older apps ignore the new field and the new route (a test pins this).

## Why it survives a broken database

- The status lives in **Workers KV** (namespace `Status`, binding `STATUS`), not D1: key
  `app-status` holds `{ status, version, updatedAt, updatedBy }`, and `app-status-history` the last
  200 changes.
- The Worker reads it first on every `/v1` request, before the rate limiter, the session lookup
  or any route. A location keeps a read for 30 seconds (`cacheTtl`), so a change reaches every
  app within about a minute.
- A missing binding, an unreadable value or a KV error all read as "normal": a KV problem never
  takes the API down.
- During maintenance every `/v1` write (`POST`, `PUT`, `DELETE`) and the realtime socket answer
  `503` with `Retry-After` (until `until`, 30 s to 1 h, 5 minutes without it) and
  `{ "error": "maintenance", "status": … }`, without reaching D1. Reads still go through.
- The admin panel writes KV directly, so maintenance can be switched on while D1 is down. Each
  save checks the version it read (409 on a stale tab) and is kept in the history with the
  owner's Access email.

The demo rooms (`/demo`) are not gated: the demo build shows the maintenance screen from
`/v1/status`.

## Using it

Admin panel → Maintenance: switch it on, write the message, set "until", set the minimum build or
a notice, save. Agents can read it (`scripts/admin-read.sh status`, `status-history`) but not
change it.

Tests: `packages/backend/platform/test/maintenance.test.ts` (served while D1 is down, 503 on
writes, the panel saving while D1 is down, agents read-only),
`packages/contracts/fixtures/test/status-compat.test.ts` (older clients), and the app's state
machine tests in `packages/ios`.
