# Experiments

How billet runs A/B tests on real couples. The decision behind it is in the product notes
(2026-11-02, "Audience, core, and testing"): the core (the scene with the cat, plus notes) is
fixed in every variant, and experiments change how it looks and behaves, never whether it exists.

This page has three parts: the assignment service, the metrics, and the iOS client.

## What an experiment is

Everything lives in one place, `registry` in `packages/backend/flags/src/experiments.ts`. An entry is:

- A **key** (`room-lighting`) that names one question and is never reused for another.
- A **kind**: `experiment` (a question with one primary metric, compared variant by variant) or
  `flag` (a Labs setting the owner rolls out remotely, delivered the same way but not compared).
- A **description**: what it changes and, for an experiment, the primary metric.
- Two or more **variants** (`amber-lantern`, `fairy-lights`), each with a whole-number weight (0 is
  allowed, as long as one is above 0).
- A **default**, one of the variants: what a targeted pair outside the exposure gets.
- An **exposure**: the whole percent of targeted pairs that enter. The others get the default and
  are not analysed.
- A **status**: `draft` (only pairs with an override get it, so the owner can try it first),
  `running` (pairs enter), or `stopped` (nobody new enters; pairs already in keep their variant, so
  a test can finish cleanly).
- A **kill switch** (`killed`): the server stops delivering it to anyone, overrides included, and
  every app falls back to its built-in default.
- **Targeting**: `minAppVersion` / `maxAppVersion` (inclusive; `1.2` covers every build of 1.2;
  a build that sent no version is left out by either bound), `ageBands` (`13-17`, `18+`),
  `pairedSince` (a UTC moment such as `2026-11-05T09:30Z`: only pairs formed at or after it; see
  "New pairs only") and `pairIds` (an allow-list, at most 200). Each rule given must hold. A pair the
  rules leave out is not listed at all.

**Code fixes the shape, D1 holds the settings.** Key, kind and variant ids come only from the
registry, because the app must contain every variant (see "App Store rules"). Everything else
in an entry is only its starting configuration. The admin panel (`docs/admin.md`) saves weights,
default, exposure, status, kill switch, targeting and description to `flag_configs` in D1, with
a version number so two editors can't overwrite each other, and a line in `flag_changes` (who,
from the Access identity, and before and after) in the same batch. A saved row that no longer fits
its entry (a variant removed in code) is ignored and the registry's configuration is used.

**Edge cache.** `GET /v1/flags` reads the configurations through the colo's Cache API
(`flagConfigCacheSeconds`, 30 s). A save drops the cached copy in the colo that saved it; other
colos see it within 30 s. So a kill reaches every app on its next flags read, at most 30 s later.

**Overrides.** `pair_flag_overrides` forces one variant on one pair, for testing on the owner's
own phones. It beats the stored assignment, status and targeting, but never the kill switch, and an
override naming a variant the entry lacks is ignored.

**Age band.** The server doesn't store an age band yet, so today a rule with `ageBands` leaves
every pair out. It starts to work when the age gate stores the declared band
(decisions.md, 2026-11-02).

The unit is the **pair**. Both partners always get the same variant, because the assignment is a
function of the pair id and the key, not of a phone.

**New pairs only.** `pairedSince` keeps an experiment to pairs formed after it started: set it to the
start when switching the experiment to `running` (the admin's "Now" button fills in the current
minute). A pair's formation time is when its invite was claimed (the earliest `pair_members` row).
A pair formed earlier, or one the server no longer has (it ended), is not targeted, so its app keeps
the default. Like every assignment, a new pair's variant is stored and kept: moving `pairedSince`
later moves nobody who is already in.

## How assignment works

`packages/backend/flags`. For a pair `p` and an experiment `e`:

1. `exposure bucket = sha256("p:e")`, first 32 bits, modulo 10,000. The pair is inside the
   experiment when the bucket is below `exposure * 100`.
2. `variant bucket = sha256("p:e:variant")`, the same way, walked across the cumulative weights.
   It is a separate hash, so being early in the exposure order says nothing about the variant.
3. A pair that is inside is **stored** (`pair_flags` in D1: pair, key, variant, time) and never
   changed. Editing weights or exposure later moves nobody who is already in. A pair outside is
   worked out again on every read from the same hash, so raising exposure brings new pairs in
   and keeps the old ones where they are.

Assignment runs when the invite is claimed (`PairingObserver`). If that fails, the first
`GET /v1/flags` does the same work, so nothing is lost. A pair that was already paired when an
experiment started gets its variant on its first read.

`GET /v1/flags` (signed in, never cached for the caller) answers `{ "flags": [{ "key", "variant" }] }`.
The shape has not changed. The request may carry `X-Billet-App-Version`, which version targeting
reads.

- In this order: killed → not listed; an override → its variant; a draft → not listed; a stored
  variant → kept (a retired one becomes the default); stopped → not listed for a pair that never
  entered; not targeted → not listed; else the hash decides, and an exposed pair is stored.
- A killed, draft or unknown experiment is absent, and the client uses its default.
- A caller without a partner gets an empty list: there is no pair to assign.
- A stored variant the registry no longer lists (retired) is answered with the default, not a
  new roll.
- A client **replaces** its stored copy with the list. It never merges into it, or switching an
  experiment off would not reach it.

## Adding an experiment

1. Build every variant into the app first, complete and reviewable (see "App Store rules"), and add
   it to `Experiments` in `RemoteFlags.swift`. A Swift test reads `experiments.ts` and fails until
   both list the same key and variants.
2. Add an entry to `registry` with `status: "draft"`. `defineExperiment` throws at start-up on a
   bad spec (fewer than two variants, every weight 0, default not among them, a weight that is not
   a whole number, exposure outside 0 to 100, a malformed version bound, a key that is not
   lowercase hyphenated words), and a test loads the registry.
3. For an experiment, choose **one primary metric** before you start and write it in the
   description. The panel also shows a fixed set of secondary and guardrail metrics for every
   experiment, and warns when a guardrail gets worse ([admin.md](admin.md#experiment-metrics)).
   They never pick the winner.
4. Deploy. Then start, stop and kill it from the admin panel, without a deploy and without an App
   Store release if the build already has the variants.
5. Leave the entry in the registry after it ends, so the key is never reused.

### Remote keys for Labs settings

Each enum Labs setting the owner may want to roll out has a key. Each is a `flag` in `draft`, with
all its weight on today's standard value, so starting one changes nothing until a weight moves:

| Key | Labs setting | Variants (Swift case names in kebab-case) |
| --- | --- | --- |
| `room-lighting` | Lighting | `amber-lantern`, `off`, `fairy-lights`, `golden-hour`, `neon-night`, `candle` |
| `window-view` | Window view (the view only; weather and hour stay local) | `suburb-night`, `rainy-suburb`, `snowy-december`, `summer-cul-de-sac`, `dorm-quad`, `fire-escape`, `pink-dusk`, `sunset-beach`, `forest-cabin`, `moonlit-peaks`, `neon-street`, `rooftops-dusk`, `autumn-park`, `misty-lake`, `desert-stars` |
| `home-layout` | Home | `classic`, `immersive`, `living-window`, `night-and-day` |

### `rooms`: one room or two for new pairs

An experiment, in `draft` until the owner starts it. Variants: `both` (the default and the control:
Room and City, as before), `room-only` (Ilya's diorama) and `city-only` (the City room with the big
window). Set `pairedSince` to the start, so only new pairs enter and every existing pair keeps both.
Primary metric: both partners active on day 7 (the retention grid, filtered by variant). Also
compare notes per pair, and `RoomOpened` (which room came on screen) in the funnel builder, split
by `rooms`. On the phone it is `RoomsVariant` in `WidgetBridge`; an unknown or missing value means
`both`.

Not remote on purpose: the fake partner, the cat model and the on/off Labs experiments (they are
tester tools or not yet complete and reviewable). `home-direction` (Window Seat or Sunset Lamp) is
gone: there is one room. `shopkeeper` went with the 3D shop. A saved configuration or assignment under a key the registry no longer has
is ignored, so nothing needs cleaning up.

## On the phone

`packages/ios/features`, modules `WidgetBridge` and `FeatureHome`.

- **What the build contains.** `Experiments` (in `RemoteFlags.swift`) lists each experiment's key and
  the variants this build can show. The server can name only those: any other variant is ignored,
  as if the server had said nothing. This is what keeps remote assignment inside the App Store
  rules below.
- **Getting the answer.** When a paired account comes to the front, the app calls `GET /v1/flags`
  (`FlagsRefresher`). The answer **replaces** the held copy and is saved in the App Group
  (`remote-flags.json`), so it is there at the next launch and offline. A failed request changes
  nothing. Leaving the pair or signing out forgets it: the variants belong to the pair.
- **Which one wins.** For each remote setting (lighting, window view, Home layout): a choice made in Labs on this phone, then the pair's variant, then what the app did
  before (the standard value). So offline, on a first launch, with no partner, with
  the experiment switched off or with a variant this build lacks, the screen is the one it always
  was. "Follow the test", the first row of each of those Labs pickers, removes the Labs choice. Testers and the owner use
  Labs to look at any variant on purpose.
- **What reads it.** `WidgetFeaturesModel.lighting` is the resolved value; screens read that and
  never the raw answer. Add a typed accessor like it for each new experiment.
- **Build and system.** Every request carries `X-Billet-App-Version` and `X-Billet-OS`
  (`ClientInfo` in `Transport`), so events and flags can be read by version.
- **Counting.** `EventReporter` queues the app's events (`AppOpened` once per launch, `WidgetAdded`
  once, found with `WidgetCenter`) in a small file of names, sends them to `POST /v1/events`
  (at most 20 at a time), and keeps whatever could not be sent for the next time. `OpeningWatched`
  and `OpeningSkipped` are accepted by the server but have no producer yet: the opening lives in the
  demo client, which has no account, and the real client has none to report.

To add an experiment on the phone: build all its variants, add it to `Experiments`, add a typed
accessor that maps each variant to what the screen shows and falls back to today's behaviour, test
the mapping (every variant has a screen; an unknown one has none), then add the server entry.

## Metrics

First-party only: counts kept on our own backend, no third-party SDK, nothing sent anywhere else.

**What is recorded.** One row per person, event name and UTC day in `pair_events` (D1): the pair
(empty before pairing), the person, the name, the day, how many times, the first and last moment,
and for what the app reports, the build and system it sent with its latest report that day
(`app_version`, `os`: the same values Analytics Engine gets, in the same shapes; null for what the
server records itself, and for rows from before 2026-11-04). Nothing else: no note, image, stroke,
text, device, address or place. The names are a closed
list in `packages/contracts/domain/src/metrics.ts`:

| Name | Who records it | When |
| --- | --- | --- |
| `InviteCreated` | server | an invite code was made |
| `PairClaimed` | server | pairing succeeded, once for each partner |
| `NoteSent` | server | a note was stored (a retried send counts once) |
| `AppOpened` | app, `POST /v1/events` | the app came to the front, at most once per launch |
| `WidgetAdded` | app | this phone has a billet widget; reported once |
| `OpeningWatched`, `OpeningSkipped` | app | how the opening ended |
| the product events | app | what people do with the cat, the room, the shop, the streak, the widget and the profile: see [analytics.md](analytics.md) |

The app can report only the names in `ClientEventName`, some with a short detail (see
[analytics.md](analytics.md)), and at most 20 per request. A name the server records
itself is refused with 400. Counting never fails a request: if the database is down, the event is
lost and a fixed line is logged. Adding a name means adding it to the list, to the table above and
to `docs/privacy.md`, because it is a privacy decision.

### Analytics Engine

Each event the app reports to `POST /v1/events` and the server accepts is also written to Workers
Analytics Engine (binding `EVENTS`, dataset `billet_<stage>_events`), for slicing by build and
system with the SQL API. A refused request writes nothing. The row is fixed by
`packages/backend/platform/src/event-sink-live.ts`; never reorder it, only add at the end:

| Column | Holds |
| --- | --- |
| `index1` | the pair hash, or `unpaired` (Analytics Engine samples by this, so a pair stays together) |
| `blob1` | the event name, one the app reports (above and in [analytics.md](analytics.md)) or `AccountDeleted` |
| `blob2` | the pair hash: first 16 hex digits of SHA-256 of `billet-pair:<pair id>`; empty before pairing |
| `blob3` | the pair's stored variants, `key=variant` joined by commas in key order; empty when none |
| `blob4` | app version from `x-billet-app-version`, `<marketing>+<build>` such as `1.2.0+14`, else `unknown` |
| `blob5` | system from `x-billet-os`, such as `iOS 26.1`, else `unknown` |
| `blob6` | the event's detail (a catalogue id or a word from a closed list); empty when none |
| `double1` | `1` (sum it; read `_sample_interval` too when the dataset is sampled) |
| `double2` | the event's value: stamps for `ShopItemBought`, `ShopBundleBought`, `ShopGiftSent`, `ShopPurchaseUndone` and `ShopDailyGiftClaimed`, else `0` |

Not in the row: the user id, the Apple subject, any email, the IP address, the country or city,
and anything a note says or shows. The two headers are accepted only in exactly the shapes above;
anything else (free text, an email) is stored as `unknown`. Country is left out on purpose:
`docs/privacy.md` promises no location, and some users are minors. Adding it is a privacy-policy
change for the owner to make first.

**Why the D1 counts stay.** The funnel and the north star join one person's events across days and
need both partners of a pair (both sent a note on day 7, D1/D7/D30 retention, time to first note).
Analytics Engine keeps rows for three months and has no user id by design, so it cannot answer
those, and D30 would fall off its end. D1 stays the source for the report and the admin panel;
Analytics Engine is the high-volume stream for "which build, which system" questions. Example, with
an Analytics read token (see `docs/admin.md`):

```sql
SELECT blob4 AS app_version, SUM(_sample_interval * double1) AS opens
FROM billet_dev_events
WHERE blob1 = 'AppOpened' AND timestamp > NOW() - INTERVAL '7' DAY
GROUP BY app_version ORDER BY opens DESC
```

Because the rows carry a user and a pair id they are personal data, even without content. The App
Store privacy label has to declare usage data (product interaction) used for analytics and linked
to the user; "no third parties" keeps the label short, not empty. Rows are removed with the account
once account deletion (#21) exists.

**The funnel** (`pnpm metrics:report`, the owner only): invites made, how many inviters ended up in a
pair, pairs formed, widget added by both partners, a first note each way, time to the first note,
both partners active on day 1, 7 and 30, notes per pair per day, how many watched the opening, and
per experiment variant the north star below. Days are UTC days, counted from the day the pair formed.

**North star (proposed):** the share of pairs where **both** partners sent a note on day 7 (day 0 is
the day they paired). It measures what the product is for: a couple that is still writing to each
other a week later. Only pairs that have reached day 7 are counted, so a young pair is not a failure.
"Active" has a looser version too (a note sent or the app opened), shown next to it.

**Reading it.** The command needs a Cloudflare API token that can only read D1, so a leak can read
counts and change nothing, and the script sends `SELECT` statements and nothing else (a test checks
this). Run it through Proton Pass and never type the token:

```sh
PROTON_PASS_AGENT_REASON="billet metrics report" pp run --env-file .env.pass -- \
  env BILLET_D1_DATABASE_ID=<the stage's D1 database id> pnpm metrics:report
```

The report prints a 95% interval next to every share, and under each experiment says plainly when
there are too few pairs to pick a winner (fewer than 100 in a variant that has reached day 7).
There is no endpoint: nothing on the internet serves these numbers.

## App Store rules

The research (couple-apps.md, Must 13) reads App Review guidelines 2.5.19 and 2.3.1 as: no
hidden or dormant features, and new features must be described to the reviewer. These numbers and
that reading come from the research notes and need checking against the current guideline text
before submission. What they mean for flags:

- **Every variant in a release build is complete and reviewable.** No stub, placeholder or
  half-built variant ships behind a flag.
- **Never remote-enable code the review has not seen.** Assignment only picks between variants
  that are already in the reviewed build. The server cannot add a variant: a variant id the
  client does not know is treated as the default.
- **Labs and the fake partner do not ship in App Store builds.** They are to be compiled out, not
  hidden. This is **not done yet**: the demo client and Labs are still linked into every build, and
  removing them is the release check in issue #99. Until then, a release build must not be
  uploaded with an experiment running that depends on them.
- Describe the variants in the review notes when an experiment is running.

## What small numbers can and cannot tell you

With hundreds of pairs only large effects are visible. For a rate near 30%, with 200 pairs in
each of two variants a test reliably finds a gap of about 13 percentage points or more (80% power,
5% significance); a gap of 10 or less will often be missed or look like noise. With 50 pairs in
each, the gap has to be about 26 points. So:

- Test **bold** things: the first screen, the opening, the invite. Not shades of a button.
- One **primary metric** per test, chosen before it starts. Looking at many metrics and many
  experiments at once will produce differences that are not there.
- One or two experiments at a time. Each pair is in all running experiments, so overlapping tests
  blur each other when the numbers are this small.
- Do not stop a test the day it looks good. Decide the pair count in advance and wait for it.
- Until there are about 1,000 pairs, back every result with the real-couple beta (#39) and
  conversations with couples. The numbers say which direction to look at, not which to ship.
