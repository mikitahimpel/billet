# Experiments

How billet runs A/B tests on real couples. The decision behind it is in the product notes
(2026-11-02, "Audience, core, and testing"): the core (the scene with the cat, plus notes) is
fixed in every variant, and experiments change how it looks and behaves, never whether it exists.

This page has three parts: the assignment service, the metrics, and the iOS client.

## What an experiment is

- A **key** (`home-direction`) that names one question and is never reused for another.
- Two or more **variants** (`window-seat`, `sunset-lamp`), each with a whole-number weight.
- A **default**, one of the variants: what a pair gets when it is outside the experiment, when
  the experiment is off, and when the phone is offline and has nothing stored.
- An **exposure**: the whole percent of pairs that enter the experiment. The others keep the
  default and are not analysed.
- A **kill switch** (`killed`): the server stops delivering the experiment and every client falls
  back to its built-in default.

The unit is the **pair**. Both partners always get the same variant, because the assignment is a
function of the pair id and the key, not of a phone.

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

`GET /v1/flags` (signed in, never cached) answers `{ "flags": [{ "key", "variant" }] }`:

- Only running experiments are listed. An experiment that is off, not started or unknown to the
  caller is absent, and the client uses its default.
- A caller without a partner gets an empty list: there is no pair to assign.
- A stored variant the registry no longer lists (retired) is answered with the default, not a
  new roll.
- A client **replaces** its stored copy with the list. It never merges into it, or switching an
  experiment off would not reach it.

## Adding an experiment

1. Build every variant into the app first, complete and reviewable (see "App Store rules").
2. Add an entry to `registry` in `packages/backend/flags/src/experiments.ts`, with `killed:
   true` until you want it live. `defineExperiment` throws at start-up on a bad spec (fewer than
   two variants, default not among them, a weight that is not a whole number, exposure outside
   0 to 100, a key that is not lowercase hyphenated words), and a test loads the registry.
3. Choose **one primary metric** before you start, and write it next to the entry.
4. Deploy the server with `killed: false`. No app release is needed if the build already
   contains the variants.
5. To stop: set `killed: true` and deploy. Clients return to their defaults on their next launch
   (or sooner, when the app comes to the front). Leave the entry in the registry so the key is
   never reused.

Today the kill switch is a one-line code change and a server deploy, which takes minutes and no
App Store review. A switch the owner can flip without a deploy (a D1 row) is a possible follow-up.

## On the phone

`packages/ios`, module `WidgetBridge` and `FeatureHome`.

- **What the build contains.** `Experiments` (in `RemoteFlags.swift`) lists each experiment's key and
  the variants this build can show. The server can name only those: any other variant is ignored,
  as if the server had said nothing. This is what keeps remote assignment inside the App Store
  rules below.
- **Getting the answer.** When a paired account comes to the front, the app calls `GET /v1/flags`
  (`FlagsRefresher`). The answer **replaces** the held copy and is saved in the App Group
  (`remote-flags.json`), so it is there at the next launch and offline. A failed request changes
  nothing. Leaving the pair or signing out forgets it: the variants belong to the pair.
- **Which one wins.** A choice made in Labs > Room style, then the pair's variant, then what the
  app did before the test (the standard room). So offline, on a first launch, with no partner, with
  the experiment switched off or with a variant this build lacks, the screen is the one it always
  was. "Follow the test" in the Labs picker removes the Labs choice. Testers and the owner use
  Labs to look at any variant on purpose.
- **What reads it.** `WidgetFeaturesModel.roomStyle` is the resolved value; screens read that and
  never the raw answer. Add a typed accessor like it for each new experiment.
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
(empty before pairing), the person, the name, the day, how many times, and the first and last
moment. Nothing else: no note, image, stroke, text, device, address or place. The names are a closed
list in `packages/contracts/domain/src/metrics.ts`:

| Name | Who records it | When |
| --- | --- | --- |
| `InviteCreated` | server | an invite code was made |
| `PairClaimed` | server | pairing succeeded, once for each partner |
| `NoteSent` | server | a note was stored (a retried send counts once) |
| `AppOpened` | app, `POST /v1/events` | the app came to the front, at most once per launch |
| `WidgetAdded` | app | this phone has a billet widget; reported once |
| `OpeningWatched`, `OpeningSkipped` | app | how the opening ended |

The app can report only its four names, and at most 20 per request. A name the server records
itself is refused with 400. Counting never fails a request: if the database is down, the event is
lost and a fixed line is logged. Adding a name means adding it to the list, to the table above and
to `docs/privacy.md`, because it is a privacy decision.

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
