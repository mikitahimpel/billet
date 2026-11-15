# How a release is made

Two things ship separately: the **backend** (the Worker, stage `prod`, stack `ourio`) and the **iOS app**
(TestFlight, then the App Store). The landing site is a third, independent deploy
([landing.md](landing.md)). They meet only at the **contract** (`packages/contracts`, Effect Schema), so
a change that keeps the contract compatible ships on one side alone. The first App Store submission is
the one case that needs everything; its list is [release-checklist.md](release-checklist.md).

## Tags

A tag marks the commit that was shipped, so "what is live" is always one `git show` away.

| Tag | Marks | Example |
| --- | --- | --- |
| `api/<yyyy-mm-dd>.<n>` | a prod backend deploy | `api/2026-11-15.1` |
| `ios/<marketing>+<build>` | the commit of an app build that went to the App Store (or the TestFlight build chosen as the release candidate) | `ios/1.0.0+57` |
| `landing/<yyyy-mm-dd>.<n>` | a production landing deploy | `landing/2026-11-16.1` |

Create the tag after the deploy or the submission succeeded, on that run's commit
(`gh run view <id> --json headSha`), and push it:

```sh
git fetch origin main
git tag -a api/2026-11-15.1 <sha> -m "backend: <one line of what changed>"
git push origin api/2026-11-15.1
gh release create api/2026-11-15.1 --verify-tag --title "api 2026-11-15.1" --notes "<what changed, contract unchanged>"
```

Tags are never moved or deleted. A GitHub Release is the changelog: one paragraph, what changed for
users, whether the contract changed.

## Backend release (contract unchanged)

Use this whenever the app does not need to change: a bug fix, a faster query, a new admin tool, a new
**optional** field or a new route that today's app ignores.

1. The change is merged to `main` with CI green. Look at the diff of `packages/contracts/**` and of the
   golden fixtures: if it is empty, or **only adds** optional fields, new routes or new enum cases the
   app tolerates, it is a backend-only release. (A removal, a rename, a type change or a new *required*
   field is not: see below.)
2. Start the deploy: GitHub, Actions, Deploy, Run workflow, stage `prod`, branch `main`. Approve it in the
   `prod` environment. The deploy runs the checks again, deploys, and smoke-tests `GET /`
   (`{"service":"ourio-api"}`).
3. Check by hand: `GET /` on `https://api.ourio.mikitahimpel.com` (the API domain), the admin panel
   opens (Access), the metric you expect moved. For a migration, read the deploy log for the migration
   line.
4. Tag `api/<date>.<n>` and write the Release note.

Nothing is submitted to Apple and no TestFlight build is needed.

### What the old app must keep surviving

Every build in the field talks to the new backend until its users update, so on the wire:

- add, never remove or rename; a new field is optional with a default the old app does not need;
- a new enum case must be one the old app can ignore (the contract tests pin "older apps ignore the
  new field and the new route", [maintenance.md](maintenance.md));
- never change the meaning of a field or the unit of a number;
- the `x-billet-*` request headers and the pair/hash salts are part of the protocol: do not change them
  without a client change.

A breaking change is done in three steps, each its own release: (1) **expand**: the backend accepts and
serves both shapes; (2) **app release** with the new shape, wait for adoption; (3) **contract**: raise
`minVersion` in the admin panel (Maintenance, below) so older builds show "Update Ourio", then remove the
old shape in a later backend release.

## App release (backend unchanged)

1. Version: `MARKETING_VERSION` in `apps/ios/project.yml` and the matching value in
   `apps/ios/scripts/testflight/check-archive.sh` change together; the build number is picked by the
   workflow (`docs/testflight-ci.md`). A UI-only fix does not change `MARKETING_VERSION` for TestFlight
   builds, only for a new App Store version.
2. The GitHub variable `API_HOST` (environment `testflight`) is the host baked into the build. For a
   release candidate it **must be the prod host** (`gh variable set API_HOST --env testflight --body
   api.ourio.mikitahimpel.com`); dev builds keep the dev host. The run summary prints
   `API host: <host>`: read it.
3. Build: `gh workflow run testflight.yml --ref main` (no `-f labs=true`: a release candidate has no
   Labs) and approve the run. Install the TestFlight build and walk the checklist in
   [qa/](qa/) on a real phone.
4. App Store Connect: choose that build for the version, fill what is new, answer the review
   questions, add the review pair ([app-review-runbook.md](app-review-runbook.md)), submit. Release
   manually after approval so the backend is ready first.
5. Tag `ios/<marketing>+<build>` on the build's commit once Apple approves it, with a Release note.

## Both sides (the contract changes)

Order matters, because users update the app days after the backend:

1. Backend release that **adds** the new shape (expand), tagged `api/...`.
2. App release that uses it ([above](#app-release-backend-unchanged)).
3. When the new app has most users, raise `minVersion` if the old shape must go, then a backend release
   that removes the old shape.

Never ship the app first: a new app against an old backend breaks on day one.

## Gates, switches and rollback

- **Maintenance, minimum build, notice**: the admin panel, Maintenance ([maintenance.md](maintenance.md)).
  `minVersion` stops builds older than `<marketing>+<build>` with "Update Ourio"; maintenance refuses
  writes and shows a calm screen. Both work when the database is down.
- **Feature flags** ([release-flags.md](release-flags.md)): ship dark, switch on from the admin panel
  without any release. Prefer a flag for anything that is not ready to be seen.
- **Backend rollback**: revert the merge on `main` through a pull request and run Deploy again (the
  `prod` environment accepts only `main`). A D1 migration is not rolled back by a redeploy: write a
  forward migration. The tag of the broken deploy stays; the rollback gets its own `api/...` tag.
- **App rollback does not exist** for users who already updated: ship a fixed build, or use a flag or
  `minVersion`/maintenance to contain it. Pause a phased release in App Store Connect if the first day
  shows crashes.
- **Domains and hosts**: the API host is baked into each build (and into universal links and invite
  links). Moving the API to another host keeps the old host answering for as long as old builds live
  (a Worker on the old host that forwards to the new one).

## Who does what

| Step | Who |
| --- | --- |
| Merge, tag, Release note | the owner or the manager agent |
| Deploy `prod` (dispatch and approve) | the owner (agents never deploy prod unless the owner says so in that conversation) |
| TestFlight builds | the manager agent dispatches, the owner approves where the workflow asks |
| App Store Connect submission, answers, review notes | the owner |
| Secrets (`prod` environment, Proton Pass) | the owner |
