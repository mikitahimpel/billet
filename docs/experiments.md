# Experiments

How billet runs A/B tests on real couples. The decision behind it is in the product notes
(2026-11-02, "Audience, core, and testing"): the core (the scene with the cat, plus notes) is
fixed in every variant, and experiments change how it looks and behaves, never whether it exists.

This page is written in three parts as the pieces land: the assignment service (here), the
metrics, and the iOS client.

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
- **Labs and the fake partner do not ship in App Store builds.** They are compiled out, not
  hidden. (The client part of this lands with the iOS change.)
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
