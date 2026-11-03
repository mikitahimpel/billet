# Admin panel

A small web app for the owner: funnel numbers, experiments, flags and per-pair overrides. It is
served by the `Api` Worker under `/admin` and protected by Cloudflare Access (Zero Trust).

## What it has

| Page | Shows | Changes |
| --- | --- | --- |
| Overview | DAU and WAU (people who opened the app or sent a note), pairs created per day, pair completion (inviters who ended up in a pair), notes per pair per day, D1/D7/D30 retention (both partners active), the funnel installed → signed in → paired → first note → second day | nothing |
| Experiments | each `experiment` with its status, exposure and variants, and per variant: pairs, the north star (both sent a note on day 7) with a 95% Wilson interval, median time to first note, and the small-numbers caution | start, stop, kill, unkill |
| Flags | every registry entry (experiments and remote flags), its live configuration and version, and the history of changes with who made each | weights, default, exposure, status, kill switch, targeting, description |
| Pairs | one pair by **pair id only** (there is no search by person): members, when it formed, its Analytics Engine hash, stored variants, overrides, what it is sent now and why, event counts | set or clear an override for testing |

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
- not expired, not before `nbf`, and carries an email (service tokens are refused).

Anything else gets the same bare `403 Forbidden`, whatever the path, including a request with no
header, an expired or forged token, the wrong audience, and a Worker with no or malformed
`ACCESS_TEAM_DOMAIN` / `ACCESS_AUD` (it fails closed). Writes must also come from the panel's own
origin (`Origin` and `Sec-Fetch-Site`), so another site cannot use the Access cookie. Every page and
answer has `Cache-Control: no-store` and a strict Content Security Policy (no inline script, no
third-party anything). Each change is stored with the Access email in `flag_changes`.

Tests: `packages/backend/admin/test/access.test.ts` (missing, expired, not yet valid, wrong
audience or team, no email, unknown key, unsigned) and `packages/backend/platform/test/admin-fetch.test.ts`
(the same through the Worker, fail-closed configuration, cross-site writes).

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
4. **Store them in Proton Pass**, vault `Billet`, item `cloudflare-access`, fields `team_domain`
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

## Querying Analytics Engine

With the token from step 5, never typed:

```sh
PROTON_PASS_AGENT_REASON="billet analytics query" pp run --env-file .env.pass.analytics -- \
  sh -c 'curl -s "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/analytics_engine/sql" \
    -H "Authorization: Bearer $CLOUDFLARE_ANALYTICS_TOKEN" \
    --data "SELECT blob4 AS app_version, SUM(_sample_interval * double1) AS events FROM billet_dev_events WHERE timestamp > NOW() - INTERVAL '"'"'7'"'"' DAY GROUP BY app_version"'
```

The columns are in [experiments.md](experiments.md#analytics-engine).
