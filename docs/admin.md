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
| In the app | every event in the contract (sent by the app or counted by the server): its count in the range against the range before, a daily sparkline, the pairs that had it in the last 7 days, people, and the first and latest day it landed; one event per day on its detail page. An event never reported shows "not seen yet". "Hints against the holdout": per hint, shown to acted for the pairs that saw it against the `hints` holdout, the lift in points and how many closed it (from `event_details`; under 5 shown, no rate). "Most chosen": the top cats, shop items, room pieces, toys and tricks over the range, with stamps spent on bought items (from `event_details`, which holds no person or pair; see [analytics.md](analytics.md)) | nothing |
| Retention | pairs by the week they formed (UTC, from Monday), one row per week and one for all weeks, and columns for day 1, 3, 7, 14, 30 and 60 after forming. Three modes: **both active** (both partners opened the app or sent a note on day N), **either active**, and **both sent a note** (the north star at day 7). Filters: an experiment's variant (from `pair_flags`) and the build the pair formed on. Each cell is a share of the week's pairs that have reached that day, coloured from faint to strong within the view; hover shows the count and its 95% Wilson interval. A day no pair of the week has reached is hatched grey, and a share resting on only some of the week's pairs (the others are too young) is in italics. See [below](#retention-grid) | nothing |
| Funnels | a funnel built from 2 to 6 steps picked from the closed event list, a window (the same UTC day as step 1, within 1 day, within 7 days), counted per pair or per person, for step 1 in the last 7, 30 or 90 days or all time; per step the count, the share of the step before (95% interval on hover), and the median time from the step before; split by an experiment's variants. Saved funnels as chips. See [below](#funnel-builder) | save a funnel under a name, delete one after a confirmation |
| Trends | any event over time, by day or week: its count, unique people, unique pairs or count per pair, over 30, 90, 180 or 365 days, against the same span before (a dashed line, and the change on each total); split by app version, system or an experiment's variant (up to eight groups, the rest as "other"); every value as a table. See [below](#trends-explorer) | nothing |
| Feature usage | for each product event (cat, room, shop, streak, widget) and each area as a whole, the share of pairs active in the last 7 and the last 30 days that used it, with a bar; split by an experiment's variants side by side; the count and 95% interval on hover. See [below](#feature-usage) | nothing |
| Experiments | a table of each `experiment` with its status, exposure, variants, pairs and result; on its page the variants side by side (split, pairs, the north star with its 95% Wilson interval, median time to first note), every variant's north star on one axis as an error bar, and a plain verdict: "not enough data yet", "no difference yet", or "B looks better" only when B's interval doesn't overlap any other's; then secondary and guardrail metrics per variant, each with its 95% interval and its difference from the default, and a warning when a guardrail is worse (also a "guardrail worse" pill in the table). See [below](#experiment-metrics) | start, stop, kill, unkill, each after a confirmation |
| Flags | a table of every registry entry (experiments and remote flags) with its state, what it serves, exposure, version and who changed it; on its page a form for its configuration that shows the field-by-field diff before saving, and the history of changes with who made each | weights, default, exposure, status, kill switch, targeting, description |
| Pairs | one pair by **pair id only** (there is no search by person): members, when it formed, its Analytics Engine hash, stored variants, overrides, what it is sent now and why, event counts | set or clear an override for testing |
| Maintenance | one card: the current state with a switch, the maintenance message and "back around" time, the minimum build, the notice, the product analytics switch ([analytics.md](analytics.md#switching-it-off)), a preview of the app's maintenance screen or notice, and every change with who made it ([maintenance.md](maintenance.md)) | all of it, turning maintenance on or analytics off after a confirmation; works while D1 is down |
| Shop | every shop item, active or not, in shelf order: kind, shelf, rarity, price (and sale price while a sale holds), deals draw, state, who changed it last and when; an item's page has its form and its history ([below](#shop-catalog)) | create an item, edit it, make it active or inactive (inactive after a confirmation), move it up or down, set its price, a sale window and its place in the daily deals, upload its picture |
| Purchases | coin-pack purchases (owner pair or demo room, pack, coins, environment, status, flagged, dates), the coin ledger and the App Store notifications with what was done with each, newest first ([payments.md](payments.md#backend)). A flagged purchase is one whose refund left the pair's wallet below 0 | nothing |
| Economy | API only, no page yet: coins minted and spent per UTC day and per source, the median and p90 pair balance, how many pairs are in debt after a refund, the share of pairs holding more than N typical days of earnings, and the daily-cap hit rate per source, from the `economy_days` and `economy_pair_days` tables ([economy.md](economy.md#metrics)). Pair-level aggregates only; a figure over fewer than 5 pairs is left out | nothing |
| Audit log | every flag change, pair override and status change in one table, newest first, filterable by area | nothing |

"Installed" shows "—": installs are counted by App Store Connect, and the app reports nothing
before sign-in.

**Too few.** In the analytics views (Retention, Funnels, Trends, Feature usage, an experiment's metrics), any group of fewer than 5 pairs shows "too
few" and no number: the server leaves the count out of the answer, so neither the page nor an agent
ever sees it. Some users are minors, and a share of 2 pairs says more about those two couples than
about the app. There are no per-person timelines and no session replay, by design. All figures come from the D1 counts (`docs/experiments.md`); the panel never reads
a note, an image, an Apple identifier or a push token, and shows no user ids. What each setting
means is in [experiments.md](experiments.md#what-an-experiment-is).

## Retention grid

`GET /admin/api/retention[?variant=<key>=<variant>&version=<build>]`, built by
`buildRetentionGrid` (`packages/backend/admin/src/admin-retention.ts`) from the `pair_events` and
`pair_flags` rows the Overview reads.

- **A pair** is the people with a `PairClaimed` row under its id; it formed on the earliest of those
  days (UTC), and day N is N days after that. It is counted in day N only once that day has come.
- **Active** is `AppOpened` or `NoteSent` that day, as in the owner report (`buildReport`).
- **The build a pair formed on** is the `app_version` on its earliest row the app sent (the
  server's own rows, such as the claim, carry none). Pairs from before the column existed
  (2026-11-04) are `unknown`.
- **Checked against SQL.** `packages/backend/platform/test/admin-retention.test.ts` loads the seed
  into a migrated D1 and compares every cell, in every mode, with a hand-written query, and the
  variant and build filters with their own queries.

## Funnel builder

`GET /admin/api/funnel?steps=<a>,<b>[,…]&window=day|1d|7d&unit=pair|person[&range=7|30|90|all][&split=<key>]`,
built by `buildFunnel` (`packages/backend/admin/src/admin-funnel.ts`) from the same rows as the
Overview.

- **Steps** are names from the closed list (`metrics.ts`, `analytics.md`), 2 to 6, all different.
  `AccountDeleted` is not offered: it is written to Analytics Engine only.
- **A unit enters** at its first step 1 whose day falls in the range (default 90 days). Per pair,
  the pair's rows after pairing, whichever partner did each step; per person, all their rows.
- **Each later step** counts at the first moment it happened at or after the step before, and
  only before the window closes (end of step 1's UTC day, or 24 hours or 7 days after it). The
  rows keep each day's first and last moment, not every one, so the moment is the row's first
  when that is not earlier, else its last. A step can be placed later than it was, never
  earlier, so a conversion is never overstated.
- **Split** by an experiment key groups units by their stored variant (a person by the pair they
  joined). Everyone is always the first group.
- **Too few**: a count, its share and its median are left out when the count or the step before
  it is under 5.
- **Saved funnels** (`GET`/`POST /admin/api/funnels`, `DELETE /admin/api/funnels/<id>`) are a name
  and the definition in `admin_funnels`, with the Access email. Writes need the panel's origin,
  like every other write; the agent API lists them read-only.
- **Checked against SQL.** `packages/backend/platform/test/admin-funnel.test.ts` runs four funnels
  (both units, all three windows, ranges and up to four steps) on the seed and compares each step's
  count and median with a hand-written query, and a variant split per pair with its own.

## Trends explorer

`GET /admin/api/trends?event=<name>&metric=count|people|pairs|perPair&interval=day|week&range=30|90|180|365&split=none|version|os|variant[&key=<experiment>]`,
built by `buildTrends` (`packages/backend/admin/src/admin-trends.ts`).

- **Two sources.** D1 (`pair_events`) answers everything. Analytics Engine answers, for its last
  90 days, the count (by day, added up into weeks) and the unique pairs by day of an event the app
  reports, overall or by build or system. It has no person, no variant, and none of the names the
  server records (`NoteSent`, `PairClaimed`, `InviteCreated`), so those always come from D1, as
  does anything older than 90 days. Each point says where it came from, and the page says which
  applied. Totals are from D1.
- **Analytics Engine needs a read token in the Worker** (owner step 5's token): a deploy that adds
  `.env.pass.analytics-read` binds it as `ANALYTICS_READ_TOKEN`, with the account id. Without it,
  or when Analytics Engine fails (logged once with a fixed reason), the trends use D1 alone. The
  query is one SELECT built only from the closed event list and generated days
  (`engineSql`); the reader never logs the answer's body.
- **Build and system** are the ones the app sent (`pair_events.app_version`, `os`); a name the
  server records takes the person's build from their other rows that day; rows from before
  2026-11-04 are `unknown`.
- **Too few**: a point (or total) resting on fewer than 5 pairs (people, for what happened before
  pairing) is left out of the answer and drawn as a gap.
- **Checked against SQL.** `packages/backend/platform/test/admin-trends.test.ts` compares every
  point of five queries (each measure, day and week, each split, 30 to 180 days) and the period
  before with hand-written queries on the seed, and the reader against a stand-in for the API.

## Feature usage

`GET /admin/api/features[?split=<experiment>]`, built by `buildFeatureUsage`
(`packages/backend/admin/src/admin-features.ts`).

- **Which events.** The product events in the closed list, by area (`featureAreas`). Cat:
  `CatPetted`, `CatFed`, `CatPlayed`, `CatCalled`, `TrickDone`. Room: `DecoratingOpened` and the
  `RoomItem*` and `RoomCustomised` events. Shop: `ShopOpened`, `ShopItemViewed`, `ShopItemBought`,
  `ShopOfferViewed`, `ShopBundleBought`, `ShopDailyGiftClaimed`, `ShopGiftSent`. Streak:
  `StreakOpened`, `StreakMilestoneSeen`. Widget: `WidgetAdded`, `WidgetButtonTapped`. Each area also
  has an "any" row: pairs that used at least one of its events.
- **Of which pairs.** The share is of the pairs **active in the window**: any row of theirs after
  pairing fell in the last 7 days (today and the 6 before) or the last 30. A pair that stopped
  using the app a month ago does not count against a feature. Rows from before pairing are left
  out.
- **By variant.** With `split`, each variant of that experiment gets its own pair of columns, over
  the pairs `pair_flags` puts in it.
- **Too few**: a share whose pairs, or whose active pairs, are fewer than 5 is left out and shows
  "too few"; so does a variant's pair count.
- **Checked against SQL.** `packages/backend/platform/test/admin-features.test.ts` compares every
  row, window and variant with a hand-written query on the seed.

## Experiment metrics

Part of `GET /admin/api/experiments` (each item's `results.metrics`, `baseline` and `warnings`),
built by `buildExperimentMetrics` (`packages/backend/admin/src/admin-experiment-metrics.ts`).

- **Over the first week.** Every metric reads a pair's first week, counting only pairs at least 7
  days old, with day 0 the day the pair formed. So a variant whose pairs are younger is not judged
  on less time.

  | Metric | Role | What it is |
  | --- | --- | --- |
  | D7 both active | secondary | share of pairs where both partners opened the app or sent a note on day 7 |
  | Widget added | secondary | share of pairs where both partners added the widget on days 0 to 6 |
  | Notes per pair per day | guardrail | notes the pair sent on days 0 to 6, divided by 7, averaged over pairs |
  | App opens per pair per day | guardrail | app opens by both partners on days 0 to 6, divided by 7, averaged over pairs |
  | Crash-free share | guardrail | waiting for crash monitoring (#38); shown as "waiting" until it has data |

- **Intervals.** A share has its 95% Wilson interval, and its difference from the baseline has
  Newcombe's interval built from the two Wilson ones. A per-day rate has a normal 95% interval of
  the mean, and its difference has Welch's interval. The baseline is the experiment's default
  variant.
- **Better, worse, no clear change.** A difference is *better* or *worse* only when its whole
  interval is on one side of zero. Every metric here is better when higher. A worse guardrail is
  a red warning at the top of the section, with the difference and its interval. A worse
  secondary metric is shown but never warns.
- **Too few**: a variant with fewer than 5 measured pairs shows "too few" and no number, and no
  difference.
- **Checked against SQL.** `packages/backend/platform/test/admin-experiment-metrics.test.ts`
  compares every variant's value for each metric, and the difference for app opens, with a
  hand-written query on the seed. In the seed, `immersive` pairs open the app less often, so the
  page has a guardrail warning to show.

## Shop catalog

The shop's items and prices are rows of the D1 table `shop_items` (migration `shop_items`, which
seeds today's twelve pieces and six sold inks at today's prices, so a deploy changes nothing). The
panel's **Shop** page edits them; the app reads the active ones from `GET /v1/shop/catalog`
([architecture.md](architecture.md#the-shop-catalog)).

- **An item** has an id (never reused, never changed), a kind (`furniture`, `decor`, `mochi`,
  `room`, `ink`, `coat`, `accessory`, … an app skips a kind it does not know), a name and blurb
  (`{cat}` is the cat's name), a rarity, a price in coins, an optional sale (a price below the
  price, from and until, in your local time), a shelf (`section`), a sort order, an optional place
  in the daily-deals draw (discount and draw order), an optional minimum build, and its picture.
- **Its picture** is either a model or image the app already bundles (the bundled asset id; an app
  that does not bundle it skips the item) or a WebP, PNG or JPEG of at most 1 MiB uploaded here,
  kept in R2 under a hash of its bytes and served at `/v1/shop/art/<hash>.<ext>`.
- **Never deleted.** An item is made inactive: it leaves the shelves and can no longer be bought,
  and every pair that bought it keeps it. An ink's colours live in the app, so a new ink needs a
  release; the panel can reprice, sell or hide the ones the app has.
- **Prices are the server's.** The room prices an order from the active items at the moment it
  decides, a sale price only inside its window. The app sends the price it showed
  (`expectedPrice`): a server price above it is refused with `PriceChanged {price}` and nothing is
  charged; a lower one is charged. Changing a price therefore reaches an open Shop on its next
  order, and the app shows the new price and asks again.
- **The daily deals** are still drawn from a seed and the pair's day. The pool is the items that
  have a place in the draw, taken in their draw order: moving an item or changing the pool changes
  which deals pairs draw from then on.
- **Saves are versioned.** A form saves against the version it read; another save in between is a
  409 and the page asks you to reload. Every create, edit, activation, deactivation and reorder is
  a row in `shop_item_changes` with the Access email, the time and the item before and after, shown
  on the item's page. Writes need the panel's origin, like every other write.
- **Agents** read `GET /admin/api/agent/shop-items` and `shop-history[?limit=<1-500>]`.

### Sand3D items

The app bundles six armchair colourways, a chest of drawers and a potted monstera made with
Sand3D ([tools/sand3d](../tools/sand3d/README.md)). None of them is in the catalog: listing them,
naming them and pricing them is the owner's call, made here. Coins are earned in the app; nothing
here takes money.

| Bundled asset id | Season | Suggested name |
| --- | --- | --- |
| `armchair-frost` | winter | Frost Armchair |
| `armchair-cocoa` | winter | Cocoa Armchair |
| `armchair-blossom` | spring | Blossom Armchair |
| `armchair-meadow` | spring | Meadow Armchair |
| `armchair-sunbeam` | summer | Sunbeam Armchair |
| `armchair-ember` | autumn | Ember Armchair |
| `chest` | any | Chest of Drawers |
| `monstera-potted` | any | Potted Monstera |

The colourways' suggested names and blurbs are in
[`tools/sand3d/armchair-colourways.json`](../tools/sand3d/armchair-colourways.json).

To add one, on **Shop → New item**:

1. **Id:** the bundled asset id, such as `armchair-frost`. It can never change, so decide first.
2. **Kind and shelf:** `furniture` and `furniture`.
3. **Name, blurb, rarity, price, sort order:** your choice. The blurb may use `{cat}`.
4. **Picture:** "Bundled in the app", with the same asset id. The app draws `Item_<id>.webp` on
   the card and `Item_<id>.usdz` on the item's stage.
5. **Minimum build:** the first build that bundles the files, so older phones skip the item.
6. Leave **Active** off until you want it on the shelves. A season's colourways can go on together
   and be made inactive when the season ends; pairs that bought one keep it.

Until the Shop lists furniture from this catalog, the app's shelves still show only their own
bundled pieces (`Catalog` in `packages/ios/features/Sources/FeatureShop/Shop.swift`). An active row makes the server
sell the item, but no shelf shows it until the app reads its furniture from `GET /v1/shop/catalog`,
which is a separate app change.

## App Review pair

The **App Review** page runs the reviewer's pair ([app-review.md](app-review.md)):

- **New code** makes a 26-symbol review code that lives 1 to 30 days and revokes every earlier
  one. The code is shown once, in the page that made it; the directory keeps only its SHA-256 and
  its last four symbols. The first code also opens the review partner, an ordinary user.
- **Revoke** stops every code at once. **Wipe the pair** ends the partner's pair, which deletes
  its room, notes, photos and cat, and stills its bot.
- The page shows the live code's last four, its expiry, its claims and the last claim, and every
  action with the Access email (`review_changes`).
- `GET /admin/api/review`, `POST /admin/api/review/code {days}`, `POST /admin/api/review/revoke`,
  `POST /admin/api/review/wipe`. Not in the agent API.

## Reports

The **Reports** page lists `partner_reports`, newest first: the reason, the reported user, the
pair, the note or photo a report is about (`note_id`) and what the reporter typed. It is read-only:
act on a report (block, delete the account) within a day. Each report also logs the warning
`partner report received` with its reason, so an alert on that message reaches the team at once.
`GET /admin/api/reports[?limit=<1-1000>]`. Not in the agent API, since it holds what users typed.

`POST /v1/pair/report` has its own rate-limit group, `reports`: 10 an hour per address (an hour-long
window; the other groups count per minute), so one caller cannot flood this page or the alert. Over
the limit the route answers 429; nothing else about reporting changes.

## Seed data

`pnpm admin:seed` writes `admin-seed.sql`: about 170 made-up pairs formed over the last 10 weeks
(more each week), inviters who never pair, four builds and four iOS versions, the `home-layout`
flag split `classic`/`immersive` (immersive holds on a little better), and what each person did
each day. Pairs drift off at their own pace, and about one in seven never does. It is deterministic
(`--seed`, `--today`, `--weeks`, `--scale`). Every user and pair id starts with `seed-`, and the
file begins by deleting earlier seed rows, so it can be run again. `event_details` has no owner, so
those rows add up on each run.

```sh
pnpm alchemy dev                               # once, so the local D1 exists
pnpm admin:seed --local "$(ls .alchemy/local/d1/cloudflare-runtime-D1DatabaseObject/[0-9a-f]*.sqlite)"
```

`--local` applies it to that SQLite file; without it the script only writes the file. For a
deployed stage (the manager's call, never an agent's) the same file goes through Wrangler:
`wrangler d1 execute <database> --remote --file admin-seed.sql`. Never on `prod`.

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
   only. Store it in vault `Billet`, item `cloudflare-analytics`, field `api_token`. The panel's
   trends read Analytics Engine with it once a deploy adds `.env.pass.analytics-read`.
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
| `retention[?variant=<key>=<variant>&version=<build>]` | Retention |
| `funnel?steps=…&window=…&unit=…[&range=…&split=…]` | Funnels: one funnel |
| `funnels` | Funnels: the saved ones, and the event names a step may be |
| `trends?event=…&metric=…&interval=…&range=…&split=…[&key=…]` | Trends |
| `features[?split=…]` | Feature usage |
| `experiments` | Experiments, with per-variant results |
| `flags` | Flags: configuration, version, who changed it last |
| `flag-history[?key=<key>&limit=<1-500>]` | the history of changes (default 100) |
| `shop-items` | Shop: every item with its state and audit fields |
| `shop-history[?limit=<1-500>]` | Shop: the audit log (default 100) |
| `pairs/<pair id>` | Pairs: one pair by id only, at the panel's detail |
| `status` | Maintenance: the current service status, version, who set it |
| `status-history[?limit=<1-200>]` | Maintenance: the changes, newest first (default 50) |
| `purchases[?limit=<1-1000>]` | Purchases: purchases, coin ledger and App Store notifications, newest first (default 200) |
| `economy[?range=<1-90>&hold=<1-365>]` | Economy: coins by day and source, balance spread, hoarding and cap hit rate over `range` days (30 by default; `hold` is N days of earnings, 14 by default) |

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
    --data "SELECT blob4 AS app_version, SUM(_sample_interval * double1) AS events FROM ourio_dev_events WHERE timestamp > NOW() - INTERVAL '"'"'7'"'"' DAY GROUP BY app_version"'
```

The columns are in [experiments.md](experiments.md#analytics-engine).
