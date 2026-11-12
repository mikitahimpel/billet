# Release checklist

Written 2026-11-12 from a read of the repository, the CI logs of main and the Release workflow.
Nothing here was built, run on a Simulator or deployed; each line says what was read. BLOCKER
means the first App Store submission or a working prod fails without it. SHOULD means a reviewer
or a user will probably hit it. NICE can follow the release. "Owner" is the repository owner;
"agent" is work an agent can do without a decision.

## BLOCKER

| # | What | Where | Who |
| --- | --- | --- | --- |
| B1 | **Prod has no push key and no Sign in with Apple key.** `alchemy.run.ts` binds `APNS_KEY`, `APNS_KEY_ID`, `LIVE_ACTIVITY_PUSH`, `APPLE_SIGN_IN_KEY` and `APPLE_SIGN_IN_KEY_ID` on the `dev` stage only, and `.env.pass.release` holds only the two Cloudflare references. A prod Worker would send no drawing pushes and no widget or Live Activity pushes. Needed: add the `Apple` item to the vault `Billet Release` with the four fields, add the four `pass://Billet Release/Apple/...` lines to `.env.pass.release`, and move the bindings out of the `stage === "dev"` block (keep `DEMO_ROOM` inside it). | `alchemy.run.ts` lines 134-146, `.env.pass.release`, `docs/alchemy.md` "Deploying" | owner (vault), then agent (code) |
| B2 | **Prod Access for `/admin`.** `ACCESS_TEAM_DOMAIN` and `ACCESS_AUD` default to empty, which keeps the panel closed to everyone (safe, but the owner cannot act on reports or make the review code). Add both to `.env.pass.release` and create the Access application for the prod host. `ACCESS_AGENT_AUD` stays empty unless agents need the read routes on prod. | `alchemy.run.ts`, `packages/backend/platform/src/admin-fetch.ts`, `docs/admin.md` | owner |
| B3 | **Release build points at `DEMO_HOST`.** `testflight.yml` sets `BILLET_API_HOST` from the secret `DEMO_HOST` and `check-archive.sh` requires the two to be equal. Before the submission build, `DEMO_HOST` must be the prod host (the `Billet Release` stage, with its custom domain or `workers.dev` address), not the dev stage. The Associated Domains entitlement (`applinks:$(BILLET_API_HOST)`) and the invite links `https://<host>/i/<code>` follow the same host, so the host should be one the owner keeps for good. | `.github/workflows/testflight.yml`, `apps/ios/Nooki/Ourio.entitlements`, `apps/ios/scripts/testflight/check-archive.sh` | owner |
| B4 | **Prod has never been deployed.** `docs/alchemy.md` says the `prod` stage, the `pass://Billet Release/...` reference (a vault name with a space) and the deploy workflow on a runner are not verified. D1 migrations (21 in `packages/backend/platform/migrations/directory`, newest `20261108193531_review_pair`) are applied by the deploy itself through `Cloudflare.D1.Database("Database", { migrations })`; there is no separate "pending" step to run, and a failed migration fails the deploy. Do a first prod deploy, then `GET /` and `/v1/flags`. Also needed: the `deploy.yml` variables (`DEPLOY_RUNNER`, `DEPLOY_ENABLED`) and reviewers on the `prod` environment. | `docs/alchemy.md` "Deploy workflow", `.github/workflows/deploy.yml` | owner |
| B5 | **App Review notes need a live review code.** Pairing needs a partner, so the notes depend on the review pair (`docs/app-review.md`): run the owner's seed script on prod, make a code in the admin's App Review page (needs B2), claim it once on a device, wipe the pair, paste the code in App Store Connect. Without it a reviewer cannot get past the invite screen and the app fails guideline 2.1. Prepared: the step list and the final notes text are in `docs/app-review-runbook.md`; the review tests pass; the repository has no seed script (the first New code opens a bare partner), and nothing was run on prod. | `docs/app-review-runbook.md`, `docs/app-review.md`, `packages/backend/review` | owner |
| B6 | **App Store listing, URLs and legal fields.** The landing's `appStoreId` is `null` and `appStoreUrl` is a placeholder, so every download button says "Coming soon" (`apps/landing/src/config.ts`). Privacy policy (`/privacy`), terms (`/terms`) and support (`/support`, with `supportEmail`) exist as landing pages. Enter them in App Store Connect as the Privacy Policy URL, Support URL and Marketing URL. The draft files `docs/legal/privacy-policy.md` and `docs/legal/terms.md` still hold `<TO CONFIRM...>`, `<NAME AND ADDRESS OF THE PROVIDER>`, `<GOVERNING LAW AND COURTS>`: the landing pages are what users read, so either delete the drafts or bring them in step; and the provider's name, address and governing law need the owner. Done in a PR: Sign in with Apple wording removed from `privacy.astro`, `help.astro`, `support.astro`, `terms.astro`, `docs/privacy.md` and the two drafts, which now follow the landing pages and keep only owner placeholders. Leave `appStoreId` null until launch; at launch set it to the numeric App Store Connect app id (`6832707480` was given by the owner's brief; no repo note confirms it, check it in App Store Connect > App Information > Apple ID) and `appStoreUrl` to the real link. **Owner questions:** (1) provider legal name; (2) postal address; (3) country; (4) governing law and courts; (5) support email (`supportEmail` in `config.ts` and `<SUPPORT_EMAIL>` in `docs/privacy.md`); (6) retention periods the owner wants stated beyond the ones the policy gives (logs 7 days, usage events 3 months, Pick tonight 24 hours, notes until the pair ends; open: reports, accounts, backups); (7) the release date for "Last updated". | `apps/landing/src/config.ts`, `apps/landing/src/pages/{privacy,terms,support}.astro`, `docs/legal/*.md` | owner |
| B7 | **App Privacy answers entered in App Store Connect.** The answers are in `docs/legal/app-privacy-labels.md` and match the four manifests as read: tracking none, no tracking domains, Name, User ID, Device ID, Photos or Videos, Other User Content, Product Interaction (analytics), Other Data (all linked, none for tracking); required-reason APIs UserDefaults `CA92.1` and `1C8F.1`, system boot time `35F9.1` (the app's `ProcessInfo.systemUptime` in `LiveRoom.swift`). No file-timestamp or disk-space API is used in `apps/ios` or `packages/ios`. Enter them by hand. Re-check Purchases if `payments` is ever turned on. | `docs/legal/app-privacy-labels.md`, `apps/ios/*/PrivacyInfo.xcprivacy` | owner |

## SHOULD

| # | What | Where | Who |
| --- | --- | --- | --- |
| S1 | **Sign in with Apple is not in the app, but the policy and docs speak of it.** `SignInControls` and `SaveAccountCard` are not used by the app target (grep of `apps/ios`), so no user can link Apple, and the account is the anonymous key in the Keychain. Consequences: (a) guideline 4.8 and the token revocation duty do not apply today; (b) `DELETE /v1/account` is called with an empty `DeleteAccountRequest()` (`ServerSession.deleteAccount`), so the app never sends `appleAuthorizationCode`; the server side is built; (c) fixed in a PR (reworded to the anonymous key, no sign-in); it said "Sign in with Apple, if you add it" and `docs/privacy.md` says "you sign in with Apple". Remaining choice: when the card ships, make the delete flow run a fresh Sign in with Apple and send the code, and do B1 first. Exactly what prod needs for revocation: the `.p8` key and its id in `Billet Release`, the bindings moved out of the dev block, and `com.ourio.app` as the key's primary App ID; without them deletion still deletes everything and logs `not-configured`. | `apps/ios/Nooki/Server/ServerSession.swift`, `packages/ios/features/Sources/FeatureOnboarding`, `docs/alchemy.md` | owner decides, agent builds |
| S2 | **Done (#515): the `-perf.script` hooks are compiled out of a release build.** `OurioPerf`, `ScenePerf` and the `Hints.swift` check exist in Debug and in a build made with `BILLET_PERF_HOOKS=YES` (only the perf CI sets it); `check-archive.sh` fails an archive that carries them. | `apps/ios/Nooki/Perf/OurioPerf.swift`, `docs/release-flags.md` | agent |
| S3 | **Report and block exist for the partner, notes and Moments** (`PartnerAndAccountSections`, `NoteSheet`, `MomentViewer` call `reportPartner`; block ends the pair and bars re-pairing; the admin Reports page and a `partner report received` warning exist), and terms text is on the welcome screen and `/terms`. Gaps: a report holds no free-text field in the app (`details: nil`), the admin Reports page is read-only (act by blocking or deleting in D1 or the admin). Reporting is rate limited (`reports`: 10 an hour per address). The promise "we read every report" (`help.astro`, Settings footer) needs someone reading the alert. | `packages/backend/pairing`, `packages/backend/platform/src/rate-limit.ts`, `docs/admin.md` | owner (process), agent (limit) |
| S4 | **Demo rooms are dead code to remove** (`DemoRoom`, `/demo`, bound on `dev` only). Needs a `deleted_classes` migration and a deploy, plus the "Test rooms" paragraph of `docs/privacy.md`. | `docs/release-flags.md` "Server: test paths" | agent, owner deploys |
| S5 | **Server flags and `payments`.** All registry flags are `draft` with `payments` `off`, so the Release build (StoreKit store) shows no coin purchase UI, and `check-archive.sh` fails a mock store. Keep `payments` off and unstarted. The four owner flags (`rooms`, `home-layout`, `room-lighting`, `window-view`) are still undecided: until chosen every pair gets the default. The App Review note's line "coin packs are off" is true only while this holds. | `packages/backend/flags/src/experiments.ts`, `docs/release-flags.md` | owner |
| S6 | **CI: the `App tests (Simulator)` timeouts were not a hang** (see below). The step cap was 40 minutes against healthy runs of 28 to 39.5 minutes; raised in PR chore/release-ci. UI tests still run only on main. | `.github/workflows/ios.yml` | done in a PR |
| S7 | **Flaky UI tests on main:** `TabBarTouchTests.testTheHeaderIsTheSameOnEveryTab` (failed 4 attempts of 41 s on `dcf378f`, passed on the next runs) and `DrawCloseTests.testCloseReturnsToHome` (failed after 5 s on `dcf378f`). Read their `.xcresult` from the run's `app-tests-log` artifact before blaming load. Eight tests are skipped on GitHub Actions or "run only for shots" (`UITourTests`); the skips are by design. | `apps/ios/OurioUITests` | agent |
| S8 | **Age rating answers** are written as a table in `docs/legal/age-rating.md` for the owner to enter. Suggested, from the code, to confirm in App Store Connect: user-generated content yes (notes, drawings, photos between two paired people; report and block present), no unrestricted web access, no gambling, no purchases in this version (coins are earned, `payments` off), no medical or location content; the app stops under 13 in onboarding and the terms say 13+. Expect 12+ or 13+ because of user-generated content. | `apps/landing/src/pages/terms.astro`, onboarding | owner |
| S9 | **TestFlight what-to-test and export compliance.** `ITSAppUsesNonExemptEncryption` is `NO` (standard HTTPS only); confirm that is still true. The Labs build option is off by default and `check-archive.sh` fails a mismatch; a build uploaded with `labs=true` must never be submitted. | `apps/ios/project.yml`, `.github/workflows/testflight.yml` | owner |

## NICE

| # | What | Where | Who |
| --- | --- | --- | --- |
| N1 | Version is `0.1.0` in `project.yml` and hard-coded in `check-archive.sh`; build numbers come from App Store Connect (floor 16, `asc.py next-build`; `project.yml` default 23 is only for local builds). A `1.0.0` first release needs both files changed together. | `apps/ios/project.yml`, `apps/ios/scripts/testflight/check-archive.sh` | owner |
| N2 | The `aps-environment` entitlement is `development` in source; automatic signing at export switches it to production. Confirm once on the first archive with `codesign -d --entitlements :- Billet.app`. | `apps/ios/Nooki/Ourio.entitlements` | agent, needs an archive |
| N3 | A few `print(...)` calls on asset load failures in `Scene/`, `Room/` and `UI/ItemSheet.swift`; they print model names and errors, never user data or secrets. Move them to `Logger` if the Console should stay quiet. | `apps/ios/Nooki` | agent |
| N4 | `fatalError` only in `required init?(coder:)` of code-made views, one `layer as! CAMetalLayer` (`RoomRenderLoop.swift`, the layer class is set in the same type), and `preconditionFailure` on a missing bundled `coin-packs.json` and in `ScenePath` parsing of shipped paths. No `try!` in app or package sources. Nothing found in the launch path that can crash from outside input. | `apps/ios`, `packages/ios` | none |
| N5 | Support for iPad is off (`TARGETED_DEVICE_FAMILY: 1`, portrait only), which is consistent; minimum iOS is 18.0. | `apps/ios/project.yml` | none |

## Read and found fine

- **Info.plist:** the only usage string is the camera (`NSCameraUsageDescription`, the invite scan);
  photos use the system picker (no library string needed); no location, contacts, microphone,
  tracking or Face ID code. No `UIBackgroundModes` (no silent-push or background task code found).
  No ATS exception: `Backend.baseURL` makes `https` unless the host is `localhost` or `127.0.0.1`.
- **Entitlements:** app group `group.com.ourio.app` on the app and all three extensions;
  Keychain group `$(AppIdentifierPrefix)com.ourio.app`; push; associated domains. Bundle IDs:
  `com.ourio.app`, `.widget`, `.notification-service`, `.share`.
- **Icon and launch:** one 1024 px `AppIcon.png`, no alpha; launch screen is the
  `LaunchBackground` color.
- **Labs and Debug:** Settings Labs and Testing are behind `#if DEBUG || LABS_YES`;
  `BILLET_LABS_MODE` defaults to `NO`; the TestFlight workflow sets `BILLET_LABS` only when its
  `labs` input is true. Shot fixtures are `#if DEBUG`. The host comes only from `BilletAPIHost`.
- **Backend (read):** admin routes sit behind the Access check and answer nothing while its
  variables are empty; a Content-Security-Policy and security headers are set on them. There is
  no CORS code, which is right for a native client. Rate limits per minute and client: auth 30,
  pairing 20, review 5, media 60, events 60, purchases 30, onboarding 60, links 30, titles 120, reports 10 an hour; a
  broken counter lets requests through. Worker logs are labels and reasons, with query strings
  redacted and 15% head sampling on prod (`API_SAMPLING_RATE`); I found no logging of tokens,
  names or note text.
- **Stage and secrets list for prod:** Cloudflare account id and API token (Workers Scripts, D1,
  R2 edit), `APNS_KEY`, `APNS_KEY_ID`, `APPLE_SIGN_IN_KEY`, `APPLE_SIGN_IN_KEY_ID`,
  `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, `TMDB_TOKEN` (without it prod serves no titles),
  optional `ANALYTICS_READ_TOKEN`, `LIVE_ACTIVITY_PUSH=on` when the Live Activity lane is wanted.
  Resources made by the deploy: D1 `Database`, R2 `Media`, KV `Status` and `Titles`, Analytics
  Engine dataset `billet_prod_events`, Durable Object `PairRoom`.

## Why `App tests (Simulator)` timed out on main

Read from `gh run view --log` of runs 43084581058 (`dcf378f`), 43111285058 (`d0044d2`) and
43103770947 (`84fbfa0`).

- `d0044d2`: the step was cut at its 40-minute cap (22:23:30 to 23:03:44) while the last UI test
  (`WelcomeTests.testWelcomeFitsTheScreen`) was running; every earlier test had passed, each
  taking 25 to 77 s. Not a hang: no test passed its own limit.
- `dcf378f`: did not time out. It ran 38.5 minutes and failed on real test failures
  (`DrawCloseTests.testCloseReturnsToHome`, `TabBarTouchTests.testTheHeaderIsTheSameOnEveryTab`).
- `84fbfa0` passed in 39.5 of the 40 minutes; the run before it (`22faceff`) passed in 28. The
  step is a 22 minute build plus 10 to 17 minutes of UI tests on a shared runner, so the cap sat
  one slow run from failing.
