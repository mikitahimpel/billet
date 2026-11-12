# App Review runbook (the reviewer's pair)

For the owner, or an agent with the prod admin open, once the `prod` stage exists
([release-checklist.md](release-checklist.md) B1 to B4). Design and reasons: [app-review.md](app-review.md);
admin page: [admin.md](admin.md#app-review-pair).

Rules: an agent never runs prod deploys or reads the vault without the owner's say. Never paste the
review code in a log, a PR, a chat or a commit. The code is shown once, in the admin page that made it.

## What exists, what does not (read 2026-11-12)

- Exists: `ReviewService` (`packages/backend/review`), `POST /v1/review/claim`, the admin
  **App Review** page and its routes, the app's invite field (it sends a 26-symbol code to the
  review route), migration `20261108193531_review_pair`.
- **There is no seed script in the repository.** The review partner is an ordinary `users` row made
  by the first **New code** (`partnerOrOpen` in `review-service.ts`): no name, no seeded notes or
  photos, no saved profile. `docs/app-review.md` lists "a seed of notes and photos" as not built.
  If the owner has a private seed script, step 2 below is where it runs; the command shape is given,
  but it is not verified. The partner's bot (`DemoBots.start`) answers notes once a reviewer claims.

## 0. Preconditions

- [ ] Prod deployed and `GET https://<prod host>/` and `/v1/flags` answer (B4).
- [ ] Access for `/admin` on prod works for the owner's email (B2).
- [ ] The prod host is the one in the submitted build (`DEMO_HOST`, B3).
- [ ] The build for review is installed from TestFlight on a real device, `payments` flag still off.

## 1. Open the prod admin

Browse to `https://<prod host>/admin`, sign in through Access, open **App Review**. Expect: no
partner yet, no codes, no changes. (An agent: read-only agent routes do not include this page;
the owner clicks.)

## 2. Seed the partner (only if the owner has a seed script)

```sh
PROTON_PASS_AGENT_REASON="seed the App Review partner on prod" \
  pp run --env-file .env.pass.release -- <the owner's seed command> --stage prod
```

`.env.pass.release` today holds only the two Cloudflare references (B1/B2 add the rest). Do this
before step 3 only if the script needs to create the partner itself; otherwise skip it, step 3
creates the partner. Check the page afterwards: it shows the partner.

## 3. Create the review code

1. **New code**, expiry 14 days (allowed 1 to 30; a week covers a normal review, longer costs nothing).
   It revokes every earlier code.
2. Copy the 26 symbols shown once. Store them in the vault item the owner chooses (not in the repo).
3. The page shows last four, expiry, claims 0.

## 4. Test-claim on a device

1. Delete the app, reinstall the review build (fresh anonymous account).
2. Welcome > **I have an invite code**, type the code.
3. Expect: paired, a room, the cat. Draw and send a note; the partner replies in a few seconds. Add a
   photo in Moments, pet the cat. Open Settings > Partner: Report partner, Block partner and
   Unpair are there; Settings > Delete account is there.
4. Admin: claims 1, last claimed now, pair present.
5. A wrong code must show the ordinary invalid-invite error (404 `InvalidInvite`), not a crash.

## 5. Wipe so the reviewer starts clean

Admin > **Wipe the pair**. Then on the test phone delete the app (the test account is paired to a
room that no longer exists). Expect: pair gone in the page, the change listed with your email.
Do not claim again before submitting: a second claim by the reviewer replaces any earlier pair
anyway, but a clean wipe leaves the partner with no leftovers.

## 6. App Store Connect (owner)

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

## 7. During review

Check the admin page once a day: claims, last claim. If the reviewer is stuck (code not accepted,
expired, 503): make a new code (revokes the old), reply in Resolution Center with the new code.
Never reuse a code across submissions.

## 8. After review

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
- The owner's seed script (not in the repository).
- The Settings labels in step 4 and 6 were matched against `docs/` and `help.astro`, not run on a device.
- Verified without deploying: `pnpm turbo run test --filter=@billet/backend-review --filter=@billet/backend-admin` passes (review service, repository contract, admin review routes).
