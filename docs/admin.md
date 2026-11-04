# Admin panel

A small web app for the owner: funnel numbers, experiments, flags and per-pair overrides. It is
served by the `Api` Worker under `/admin` and protected by Cloudflare Access (Zero Trust).

## What it has

A left sidebar with the pages below; a top bar with the stage the Worker was deployed as (`DEV`
in amber, `PROD` in red, from the `STAGE` binding Alchemy sets), when the page's data was loaded
(with a reload button) and the signed-in Access email. Tables can be sorted by any column, searched
and filtered, and a row opens its detail page. Times read "3 days ago", with the exact time on
hover.

| Page | Shows | Changes |
| --- | --- | --- |
| Overview | for the last 7, 30 or 90 days against the same span before it: daily active (mean per day), weekly active (on the last day), new pairs, pair completion (inviters whose first invite fell in the range and are now in a pair), notes per pair per day (notes over the days each pair existed), D1/D7 retention (pairs formed in the range, both partners active on day N), each with its change and a sparkline or its 95% interval; active people and notes per day; the funnel installed → signed in → paired → first note → second day (all time) with each step's conversion from the one before | nothing |
| In the app | every event in the contract (sent by the app or counted by the server): its count in the range against the range before, a daily sparkline, the pairs that had it in the last 7 days, people, and the first and latest day it landed; one event per day on its detail page. An event never reported shows "not seen yet". "Most chosen": the top cats, shop items, room pieces, toys and tricks over the range, with stamps spent on bought items (from `event_details`, which holds no person or pair; see [analytics.md](analytics.md)) | nothing |
| Experiments | a table of each `experiment` with its status, exposure, variants, pairs and result; on its page the variants side by side (split, pairs, the north star with its 95% Wilson interval, median time to first note), every variant's north star on one axis as an error bar, and a plain verdict: "not enough data yet", "no difference yet", or "B looks better" only when B's interval doesn't overlap any other's | start, stop, kill, unkill, each after a confirmation |
| Flags | a table of every registry entry (experiments and remote flags) with its state, what it serves, exposure, version and who changed it; on its page a form for its configuration that shows the field-by-field diff before saving, and the history of changes with who made each | weights, default, exposure, status, kill switch, targeting, description |
| Pairs | one pair by **pair id only** (there is no search by person): members, when it formed, its Analytics Engine hash, stored variants, overrides, what it is sent now and why, event counts | set or clear an override for testing |
| Maintenance | one card: the current state with a switch, the maintenance message and "back around" time, the minimum build, the notice, the product analytics switch ([analytics.md](analytics.md#switching-it-off)), a preview of the app's maintenance screen or notice, and every change with who made it ([maintenance.md](maintenance.md)) | all of it, turning maintenance on or analytics off after a confirmation; works while D1 is down |
| Audit log | every flag change, pair override and status change in one table, newest first, filterable by area | nothing |

"Installed" shows "—": installs are counted by App Store Connect, and the app reports nothing
before sign-in. All figures come from the D1 counts (`docs/experiments.md`); the panel never reads
a note, an image, an Apple identifier or a push token, and shows no user ids. What each setting
means is in [experiments.md](experiments.md#what-an-experiment-is).

## Why the same Worker

The panel needs the same D1 directory, the same flags service and the same funnel code as the API.
In the `Api` Worker it shares them without a second deploy target, a second D1 binding or a copy of
the rules. The cost is a larger surface on the public Worker, so the Access check runs before any
`/admin` routing and fails closed (below). A separate Worker would be worth it if the panel grows
its own dependencies; the code is in `packages/backend/admin` and `admin-fetch.ts`, so moving it
is a new composition root, not a rewrite.

## How it is protected

Cloudflare Access sits in front of `/admin` at the edge and only lets the owner's email through.
The Worker does not trust that alone: `packages/backend/platform/src/admin-fetch.ts` verifies the
`Cf-Access-Jwt-Assertion` header on **every** `/admin` request before routing:

- RS256 signature against the team's keys (`https://<team>.cloudflareaccess.com/cdn-cgi/access/certs`,
  cached by Cloudflare for 10 minutes);
- issuer is the configured team domain, audience contains the configured AUD tag;
- not expired, not before `nbf`;
- a person (a token with an email) must carry the panel's AUD. A service token (a `common_name`,
  no email) must carry the agent application's AUD (`ACCESS_AGENT_AUD`), and may only `GET`
  `/admin/api/agent/...` ([Agent API](#agent-api)).

Anything else gets the same bare `403 Forbidden`, whatever the path, including a request with no
header, an expired or forged token, the wrong audience, a service token anywhere outside the agent
reads or sending any write, and a Worker with no or malformed `ACCESS_TEAM_DOMAIN` / `ACCESS_AUD`
(it fails closed; without a valid `ACCESS_AGENT_AUD` only the agent API is closed). Writes must also come from the panel's own
origin (`Origin` and `Sec-Fetch-Site`), so another site cannot use the Access cookie. Every page and
answer has `Cache-Control: no-store` and a strict Content Security Policy (no inline script, no
third-party anything). Each change is stored with the Access email in `flag_changes`.

Tests: `packages/backend/admin/test/access.test.ts` (missing, expired, not yet valid, wrong
audience or team, no identity, service tokens for the wrong audience, unknown key, unsigned) and
`packages/backend/platform/test/admin-fetch.test.ts` (the same through the Worker, fail-closed
configuration, cross-site writes, and every write and panel route refused to a service token).

## Owner steps (once)

Nothing here has been done in the Cloudflare account. The steps for the owner:

1. **Pick the host.** The panel lives on the API's custom domain, at `https://<api host>/admin`.
   Not a `workers.dev` address: Access can't protect a path there, and it would go in the logs.
2. **Create the Access application.** Zero Trust → Access → Applications → Add an application →
   Self-hosted.
   - Name `billet admin`; session duration 24 hours.
   - Public hostname: the API host, path `admin` (this covers `/admin` and everything under it).
   - Policy: action Allow, name `owner`, Include → Emails → the owner's email. Nothing else.
   - Login method: One-time PIN is enough.
3. **Copy two values.** The application's **AUD tag** (Applications → billet admin → Overview,
   64 hex digits) and the **team domain** (Settings → Custom pages: `<team>.cloudflareaccess.com`).
4. **Store them in Proton Pass**, vault `Billet`, item `Cloudflare Access`, fields `team_domain`
   and `aud`. `.env.pass` already refers to them (`ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`); the deploy
   passes them to the Worker. Not secrets, but kept out of this public repo.
5. **Analytics read token** (for Analytics Engine SQL, not needed by the panel): My Profile → API
   Tokens → Create token → Custom: Permissions Account → Account Analytics → Read, this account
   only. Store it in vault `Billet`, item `cloudflare-analytics`, field `api_token`.
   `.env.pass.analytics` refers to it.
6. **Deploy** through the manager, with the owner's OK for the exact commit (`docs/alchemy.md`).
   Until `ACCESS_TEAM_DOMAIN` and `ACCESS_AUD` reach the Worker, `/admin` answers 403 to everyone.

## Opening it

Go to `https://<api host>/admin`, sign in with the one-time PIN sent to the owner's email, and the
Overview loads. If it says 403 after signing in, the Worker's `ACCESS_AUD` or `ACCESS_TEAM_DOMAIN`
does not match the application (step 3).

## Agent API

Agents (Claude Code sessions working on billet) read the same data the panel shows, as JSON, with
a Cloudflare Access **service token**. They can't change anything.

| Route (`GET /admin/api/agent/...`) | Same as the panel's |
| --- | --- |
| `overview[?days=7\|30\|90]` | Overview (30 days by default) |
| `experiments` | Experiments, with per-variant results |
| `flags` | Flags: configuration, version, who changed it last |
| `flag-history[?key=<key>&limit=<1-500>]` | the history of changes (default 100) |
| `pairs/<pair id>` | Pairs: one pair by id only, at the panel's detail |
| `status` | Maintenance: the current service status, version, who set it |
| `status-history[?limit=<1-200>]` | Maintenance: the changes, newest first (default 50) |

- The answers carry the same fields as the panel's, so the Overview's `range` and `stats` and an
  experiment's `results.verdict` are there too. Routes and access are as before.
- The Worker serves these only to a token whose `common_name` is set and whose audience is the
  agent application's AUD. Only `GET`; every write route, the page and the panel's own API answer
  `403` to a service token. Changes stay with the owner's email.
- Each read is logged (Workers logs) as `admin agent read` with the token's `common_name` (its
  client id, not the secret) and the path.
- `scripts/admin-read.sh <route>` sends the `CF-Access-Client-Id` / `CF-Access-Client-Secret`
  headers and prints the JSON. The credentials come from `.env.pass.agents`; the API host from a
  local file that is never committed (`~/.config/billet/admin.env`, a line
  `BILLET_ADMIN_HOST=<host>`, or `BILLET_ADMIN_HOST` in the environment):

```sh
PROTON_PASS_AGENT_REASON="read experiment results" pp run --env-file .env.pass.agents -- \
  scripts/admin-read.sh experiments
```

### Owner steps for the agent API (once)

Agents never create credentials; the owner does.

1. **Create the service token.** Zero Trust → Access → Service credentials → Service Tokens →
   Create Service Token, name `billet-agents`, duration as you like (a year is fine; renew it
   before it ends). Copy the Client ID and the Client Secret: the secret is shown only once.
2. **Store it in Proton Pass**, vault `Billet`, item `cloudflare-agents`, fields `client_id` and
   `client_secret`.
3. **Create the agents' Access application.** Zero Trust → Access → Applications → Add →
   Self-hosted: name `billet admin agents`, hostname the API host, path `admin/api/agent`. Policy:
   name `agents`, action **Service Auth**, Include → Service Token → `billet-agents`. Nothing else.
   Access uses the most specific path, so this application, not `billet admin`, guards the agent
   routes, and a browser login can't reach them.
4. **Copy its AUD tag** into item `Cloudflare Access`, field `agent_aud`. It is optional:
   `.env.pass.agent-access` passes it to the Worker as `ACCESS_AGENT_AUD`, and a deploy adds that
   file (`--env-file .env.pass --env-file .env.pass.agent-access`) only once the field exists.
   Without it the agent API stays closed.

## Querying Analytics Engine

With the token from step 5, never typed:

```sh
PROTON_PASS_AGENT_REASON="billet analytics query" pp run --env-file .env.pass.analytics -- \
  sh -c 'curl -s "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/analytics_engine/sql" \
    -H "Authorization: Bearer $CLOUDFLARE_ANALYTICS_TOKEN" \
    --data "SELECT blob4 AS app_version, SUM(_sample_interval * double1) AS events FROM billet_dev_events WHERE timestamp > NOW() - INTERVAL '"'"'7'"'"' DAY GROUP BY app_version"'
```

The columns are in [experiments.md](experiments.md#analytics-engine).
