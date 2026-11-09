# App Review: the reviewer's pair

**Status: built; needs the owner's OK and a code on prod before the first submission.** The
backend is `packages/backend/review` (`ReviewService`, `POST /v1/review/claim`), the controls are
the admin's **App Review** page ([admin.md](admin.md#app-review-pair)), and the app's invite field
takes the 26-symbol code and sends it to the review route. Not built: a seed of notes and photos
for the partner, dropping the reviewer's push tokens on a wipe, and leaving the review pair out of
experiment assignment (it is already out of the funnel).

App Review guideline 2.1 needs the reviewer to use the whole app. Billet needs two paired
accounts, and a reviewer has one device and no partner. The answer is a **review invite code**: a
long secret that pairs the reviewer with a reserved review partner, using the screens real users
already have.

There is no review build, no flag and no demo route on prod. The `demo-partner` routes stay
dev-stage only (`settingsForStage`, `packages/backend/payments/src/payments-config.ts`).

## What the reviewer does

Sign-in is anonymous (a key in the Keychain, no login), so there are no credentials to hand over.

1. Install the build and open it. The app signs in on its own.
2. Tap **I have an invite code** on the welcome screen.
3. Type the review code from the App Review notes. The reviewer is now paired with the review
   partner and sees a room with a cat, notes and photos already in it.
4. Draw and send a note, add a photo, pet the cat. The review partner answers (see below).

## What the backend does

Each piece is a plain addition, with no special case for the reviewer inside the normal sign-in
and pairing rules: a claim makes an ordinary invite for the partner and claims it for the
reviewer.

- **The review partner.** One ordinary user that we create and own, on prod only, from a seed
  script run by the owner (never by an agent). It has a name, a seeded cat state, a handful of
  notes and photos, and a saved profile. It is a real `users` row with a pair slot, not a bot
  that skips checks.
- **A reserved code type.** Today an invite is 10 symbols from a 32-symbol alphabet, valid 24
  hours, claimed once (`pairing-service.ts`). A review code is a different kind of row:
  - at least 128 bits (for example 26 characters of the same alphabet), so it cannot be guessed
    or enumerated; it is stored only as a hash, like every invite;
  - **reusable** while valid (a reviewer may reinstall, and App Review may use several devices),
    and each claim pairs that claimer with the review partner. Because a partner holds one
    pair, a second claimer replaces the first: the review pair is reset on each claim;
  - **revocable** and with an **expiry**, both set from the admin, never from the app;
  - the app's code field accepts the longer length for this kind only.
- **Bot behaviour limited to that pair.** The review partner answers notes, reacts to photos and
  cares for the cat, as the dev demo partner does (`packages/backend/demo-partner`). The
  behaviour is keyed on the one reserved user id, so no other pair can ever get a bot.
- **Admin controls** (`docs/admin.md`): create or rotate the review code with an expiry, revoke
  it, see whether it is live and when it was last claimed, and **wipe the pair** (notes, photos,
  cat state, pair row) and reseed the partner. Every action is written to the admin audit trail.
- **Limits so it cannot be abused:**
  - claims go through the existing per-IP rate limit, with a stricter budget for the review code
    route, and failed attempts are counted like any invalid invite;
  - the code does nothing after its expiry or revocation, and a code row never turns a user
    into an admin or touches another pair;
  - the review pair is excluded from the usage counts and experiment assignment, so review
    traffic does not skew metrics;
  - the partner's bot sends nothing outside the pair, and push tokens of the reviewer's
    devices are dropped when the pair is wiped;
  - the code is never logged, and the admin shows only its last four characters after
    creation.

## Before each submission

1. In the admin's **App Review** page on prod, make a new code (owner) that expires after the
   expected review window (a week is enough; make a new one if review runs long). The first code
   opens the review partner.
2. Paste the code into the App Review notes below. Put nothing else secret in them.
3. Claim it once on a real device from a fresh install to check the room, then **wipe the pair**
   so the reviewer starts clean.

## After review

Revoke the code and wipe the pair in the admin. Rotate the code for the next submission rather
than reusing it.

## Text for App Store Connect's review notes

> Billet is a private app for two people, so it needs a partner. We have prepared one for you.
> You do not need an account or a password: the app signs in on its own.
>
> 1. Open the app. On the first screen tap **I have an invite code**.
> 2. Enter this code: `<REVIEW CODE>` (valid until `<DATE>`).
> 3. You are now paired with our review partner and see a shared room, a cat and some notes.
> 4. To send a note, tap the draw button, draw something and send it. The partner replies in a
>    few seconds. You can also add a photo in Moments and pet the cat on the Home screen.
>
> The coin packs are off in this version: nothing in the app can be bought with money. Pairing
> with a real partner works by sharing a 10-character invite code from **Us > Invite**; the code
> above is the same screen with a longer code.
> Contact: <SUPPORT_EMAIL>

(Check the last two sentences against the release before submitting: the coin-pack line is true
while the `payments` flag stays off, see `docs/release-flags.md`.)
