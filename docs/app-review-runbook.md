# App Review runbook (the reviewer's pair)

For the owner, or an agent with the prod admin open, once the `prod` stage exists
([release-checklist.md](release-checklist.md) B1 to B4). Design and reasons: [app-review.md](app-review.md);
admin page: [admin.md](admin.md#app-review-pair).

Rules: an agent never runs prod deploys or reads the vault without the owner's say. Never paste the
review code in a log, a PR, a chat or a commit. The code is shown once, in the admin page that made it.

## What exists, what does not (read 2026-11-13)

- Exists: `ReviewService` (`packages/backend/review`), `POST /v1/review/claim`, the admin
  **App Review** page and its routes, the app's invite field (it sends a 26-symbol code to the
  review route), migration `20261108193531_review_pair`.
- **The seed is built into the claim.** There is no seed script to run, and there cannot be one
  that holds: a claim ends the partner's earlier pair, which deletes its room and notes, so
  anything written before the claim is gone. Instead each claim starts the partner's bot with
  three welcome notes (`reviewWelcomeNotes`, `review-service.ts`) that it sends in the first
  seconds, then it answers, reacts and cares for the cat as the demo bot does
  (`DemoBots.start`, `demo-bot.ts`).
- **Not built:** photos in the room, and a name or saved profile for the partner (the backend has
  no partner name; the app shows the room's own labels). The reviewer adds the first photo.
- **Agents cannot do any of this.** Access service tokens may only `GET /admin/api/agent/...`;
  the App Review routes answer 403 to them ([admin.md](admin.md#agent-api)). That is on purpose:
  no script creates the code, the owner clicks it in the admin.

## 0. Preconditions

- [ ] B1 to B4 of [release-checklist.md](release-checklist.md) are done, in this order. B2 first
      matters most here: put `ACCESS_TEAM_DOMAIN` and `ACCESS_AUD` of the prod Access application
      in `.env.pass.release`, created for the prod host and for the owner's email only. Leave
      `ACCESS_AGENT_AUD` empty.
- [ ] Prod is deployed by the owner ([alchemy.md](alchemy.md), "Deploy workflow") and
      `GET https://<prod host>/` and `/v1/flags` answer (B4).
- [ ] The prod host is the one in the submitted build (`DEMO_HOST`, B3).
- [ ] The build for review is installed from TestFlight on a real device, `payments` flag still off.

## 1. Open the prod admin

Browse to `https://<prod host>/admin`, sign in through Access with the owner's email, open
**App Review**. Expect: no partner yet, no codes, no changes. A `403` here means B2 is not right
(wrong AUD or team domain), fix that before going on.

## 2. Create the review code

1. **New code**, expiry 14 days (allowed 1 to 30; a week covers a normal review, longer costs nothing).
   It revokes every earlier code.
2. Copy the 26 symbols shown once. Store them in the vault item the owner chooses (not in the repo).
3. The page shows last four, expiry, claims 0.

## 3. Test-claim on a device

1. Delete the app, reinstall the review build (fresh anonymous account).
2. Welcome > **I have an invite code**, type the code.
3. Expect: paired, a room, the cat, and within a few seconds three notes from the partner
   ("hi, I'm so glad you're here" and two more). Draw and send a note; the partner replies in a few seconds. Add a
   photo in Moments, pet the cat. Open Settings > Partner: Report partner, Block partner and
   Unpair are there; Settings > Delete account is there.
4. Admin: claims 1, last claimed now, pair present.
5. A wrong code must show the ordinary invalid-invite error (404 `InvalidInvite`), not a crash.

## 4. Wipe so the reviewer starts clean

Admin > **Wipe the pair**. Then on the test phone delete the app (the test account is paired to a
room that no longer exists). Expect: pair gone in the page, the change listed with your email.
Do not claim again before submitting: a second claim by the reviewer replaces any earlier pair
anyway, but a clean wipe leaves the partner with no leftovers.

## 5. App Store Connect (owner)

App Information > App Review Information > Notes: paste the text below with the code and date
filled. Sign-in required: **No** (the app signs in on its own). Contact details: the support email.

```
Ourio is a private app for two people, so it needs a partner. We have prepared one for you.
No account or password is needed: the app signs in on its own.

1. Open the app. On the first screen tap "I have an invite code".
2. Enter this code: <REVIEW CODE> (valid until <DATE>).
3. You are now paired with our review partner and see a shared room, a cat and some notes.
4. Tap the draw button, draw something and send it. The partner replies in a few seconds.
   You can also add a photo in Moments and pet the cat on the home screen.

There are no payments in this version: nothing in the app can be bought with money.
Real pairing works with a 10-character invite code from the Us tab; the code above is the same
screen with a longer code.

User safety: Settings > Partner has "Report partner", "Block partner" and "Unpair". Reports
are logged and we read them. Settings > Delete account deletes the account and
everything it sent, and unpairs the partner.

Content in the app is only what the two paired people send each other: there is no public feed
and no way to find or message strangers. The app is for ages 13 and older.

Contact: <SUPPORT_EMAIL>
```

Before pasting, re-read it against the build: the Settings labels (`PartnerAndAccountSections.swift`),
"Us tab" (`docs/ios-architecture`), and `payments` off (S5).

## 6. During review

Check the admin page once a day: claims, last claim. If the reviewer is stuck (code not accepted,
expired, 503): make a new code (revokes the old), reply in Resolution Center with the new code.
Never reuse a code across submissions.

## 7. After review

Admin > **Revoke**, then **Wipe the pair**. Rotate rather than reuse for the next submission.

## Rollback

| Problem | Do |
| --- | --- |
| Code leaked or pasted wrongly | **Revoke** in the admin. Make a new code; edit the notes. |
| Pair in a bad state, bot silent | **Wipe the pair**, then claim again from a fresh install. |
| Claim route failing on prod (503 `Unavailable`, `review unavailable` in logs) | Revoke the code, tell App Review in Resolution Center, fix, redeploy per `docs/alchemy.md`; the migration only adds tables, so a code rollback of the Worker is safe. |
| Review feature must be gone | Revoke the code: the route then answers 404 for every code and affects no other user. |

## Unverified (no deploy was done)

- Everything on prod: Access, the admin page, a real claim, the bot reply, push on prod.
- The welcome notes in a real room: the bot's state machine and the claim are tested
  (`demo-bot.test.ts`, `review-service.test.ts`), the Durable Object and a phone are not.
- The Settings labels in step 3 and 5 were matched against `docs/` and `help.astro`, not run on a device.
- Verified without deploying: `pnpm turbo run test --filter=@billet/backend-review --filter=@billet/backend-admin` passes (review service, repository contract, admin review routes).
