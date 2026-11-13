# TestFlight from GitHub Actions

`.github/workflows/testflight.yml` archives the app on a GitHub `xcode-27` runner (Xcode from `.xcode-version`), checks the archive and
uploads it to TestFlight. It only runs when started by hand, and each run waits for the repository
owner's approval before it can read any secret.

## Running it

```sh
gh workflow run testflight.yml --ref main
gh workflow run testflight.yml --ref main -f build=17   # a particular build number
gh workflow run testflight.yml --ref main -f build=20 -f commit=4e2684c   # a hotfix from an earlier commit on main
gh workflow run testflight.yml --ref main -f labs=true   # the owner's test build, with Settings > Labs
gh run watch "$(gh run list --workflow testflight.yml --limit 1 --json databaseId -q '.[0].databaseId')"
```

Approve the run on its page (Review deployments → testflight), or with
`gh api -X POST repos/mikitahimpel/billet/actions/runs/<run-id>/pending_deployments -F 'environment_ids[]=<id>' -f state=approved -f comment=ok`.

The run ends by printing one line, `build <number>: <processing state>`, also shown in the run
summary. `VALID` means testers can install it. `PROCESSING` means App Store Connect has the build and
is still working on it, which can take up to half an hour after the run ends.

### The first run for a new app

The app is `com.ourio.app` (App Store Connect record "Ourio", SKU `ourio`), with the extensions
`com.ourio.app.widget`, `.notification-service` and `.share` and the app group
`group.com.ourio.app`. The owner registers those App IDs and the record; no provisioning profile
exists for them before the first run. Automatic signing creates the profiles through the API key on
that run (`-allowProvisioningUpdates`), so the key needs its Admin role (see below). A run that
fails with "No profiles for 'com.ourio.app…'" on a fresh app is missing an App ID or a capability
(App Groups, Push Notifications, Sign in with Apple, Associated Domains) on one of them.

## What it does

1. Fails straight away, naming them, if any of the four secrets is missing.
2. Writes the App Store Connect key to a file only the runner user can read (mode 0600). The last
   step deletes it, along with the run's keychain, even when an earlier step failed. Just before
   that, the run revokes its own development certificate (see below).
3. Picks the build number: one above the highest build App Store Connect has for the app, and at
   least 16, since the local archives went up to 15. A number given with `-f build=N` is used
   instead, and the run stops if App Store Connect already has that build or a later one. The version
   stays 1.0.0 (`MARKETING_VERSION` in `apps/ios/project.yml`).
4. Generates the project with XcodeGen and archives Release with automatic signing:
   `xcodebuild archive -allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …`.
   The bundle IDs, team 2666YPBJTB and signing setup are the project's own, unchanged.
5. Runs `apps/ios/scripts/testflight/check-archive.sh` on the archive. That script checks:
   - the bundle IDs, version and build of the app and its widget;
   - `codesign --verify` and the team on both;
   - that the app was built with the StoreKit store (`BilletPayments` is `storekit` and the
     binary has no `MockPaymentsBuild`) and with Labs as asked (`BilletLabs` equals `EXPECT_LABS`,
     `NO` unless the run has `-f labs=true`), since a normal build goes on to App Review;
   - that the demo host is the app's `BilletAPIHost` and appears nowhere in git history.
6. Exports with `apps/ios/ExportOptions-external.plist` (`method` app-store-connect,
   `destination` upload, `uploadSymbols` on), which signs with a cloud-managed Apple Distribution
   certificate and uploads the build to TestFlight.

Nothing is exported from a Mac's keychain. The archive is signed with an Apple Development
certificate that Xcode creates through the API key. Distribution signing happens in Apple's cloud
when the archive is exported.

## Labs builds

`-f labs=true` archives with `BILLET_LABS=YES`, so Settings > Labs and Testing are in the build,
for the owner's own testing. The archive check then expects `BilletLabs` to be `YES`, and it
fails on a mismatch either way. The run summary says "Labs build: do not submit for review". After
upload, the build's TestFlight "What to test" note (en-US) says the same
(`asc.py what-to-test`).

Never submit a Labs build for App Review. Ship a build from a run without `labs`.

## Secrets

All four are secrets of the `testflight` environment (Settings → Environments → testflight), not
repository secrets.

| Secret          | What it is                                       | Source                                         |
| --------------- | ------------------------------------------------ | ---------------------------------------------- |
| `ASC_KEY_ID`    | The App Store Connect API key's ID               | Proton Pass, vault Billet, `Apple/asc-api` → `key_id`    |
| `ASC_ISSUER_ID` | The team's issuer ID (Users and Access → Integrations) | `Apple/asc-api` → `issuer_id`            |
| `ASC_P8`        | The key's `.p8` file, as text or base64          | `Apple/asc-api` → `p8`                         |
| `DEMO_HOST`     | The demo server's host, built into `BilletDemoHost` | `~/.billet-manager/pet-concept/demo-host.txt` |

The workflow masks `DEMO_HOST` in the log and never prints it. The host must never be committed;
the archive check fails the run if it appears anywhere in git history.

The environment has the repository owner as its required reviewer and only accepts runs from `main`.

### The key's role

Cloud signing needs a **Team** API key (not an individual key) with the **Admin** role, or with
**App Manager** plus access to certificates, identifiers and profiles. With a lesser role the archive
fails with "No signing certificate" or "requires a provisioning profile", or the export fails with
"Cloud signing permission error". Make it in App Store Connect → Users and Access → Integrations →
App Store Connect API → Team Keys. Apple lets you download the `.p8` only once.

### Setting the secrets

Values go from Proton Pass straight into `gh` and are never printed. Make an env file in the
scratchpad that holds only references:

```sh
ASC_KEY_ID=pass://Billet/Apple/asc-api/key_id
ASC_ISSUER_ID=pass://Billet/Apple/asc-api/issuer_id
ASC_P8=pass://Billet/Apple/asc-api/p8
```

Then copy each value across:

```sh
export PROTON_PASS_AGENT_REASON="billet: copy ASC key into GitHub env secret"
for name in ASC_KEY_ID ASC_ISSUER_ID ASC_P8; do
  pp run --env-file asc.env -- sh -c "printf %s \"\$$name\" | gh secret set $name --env testflight"
done
gh secret set DEMO_HOST --env testflight < ~/.billet-manager/pet-concept/demo-host.txt
```

## Rotating the key

1. In App Store Connect, make a new Team key with the same role.
2. Put its key ID and `.p8` into the Proton Pass item. The issuer ID stays the same.
3. Run the copy step above again.
4. Start a run and check that it uploads.
5. Revoke the old key in App Store Connect.

If a key leaks, revoke it first, then do steps 1 to 4.

## The development certificate

To sign the archive, Xcode makes a new Apple Development certificate through the API key on every
run ("Created via API"), with its private key in the run's keychain. The team may hold only a few.
Once they are used up, the archive fails with "Choose a certificate to revoke. Your account has
reached the maximum number of certificates" and "No profiles for 'com.ourio.app.…'".

So the step "Revoke this run's development certificate" runs at the end of every run, also after a
failure:

- `asc.py revoke-run-certificates --keychain "$KEYCHAIN"` reads the serial numbers of the
  certificates in the run's keychain. The keychain is made empty at the start of the run, so they
  are this run's.
- It looks each serial up in App Store Connect (`GET /v1/certificates?filter[serialNumber]=…`).
- It revokes only the development ones (`DELETE /v1/certificates/{id}`). Distribution
  certificates are never revoked.
- The token is the same ES256 JWT from the `ASC_*` secrets that the build-number step uses.

The step prints each certificate it revoked, or that the keychain held none. It holds none when
the archive failed before Xcode made one. The certificate only signed this run's archive.
TestFlight builds are re-signed in the cloud at export, so revoking it changes nothing for testers.

The selection is tested in `apps/ios/scripts/testflight/test_asc.py`, which CI runs:
`python3 -I -m unittest discover -s apps/ios/scripts/testflight`.

## When the certificate limit is hit again

The archive fails with "Choose a certificate to revoke". Most likely, older runs, which didn't
revoke their certificates, or a run killed before its last steps, left certificates behind.

1. List the team's certificates. This is read-only and needs the same key as the workflow:

   ```sh
   export PROTON_PASS_AGENT_REASON="billet: list Apple certificates for the TestFlight limit"
   pp run --env-file asc.env -- sh -c 'printf %s "$ASC_P8" > "$TMPDIR/asc.p8" && chmod 600 "$TMPDIR/asc.p8" &&
     ASC_KEY_PATH="$TMPDIR/asc.p8" python3 -I apps/ios/scripts/testflight/asc.py certificates; rm -f "$TMPDIR/asc.p8"'
   ```

   `asc.env` is the reference-only env file from "Setting the secrets". Each line shows the type,
   serial, expiry and name.
2. The leftovers are the `DEVELOPMENT` or `IOS_DEVELOPMENT` certificates named "Created via API".
   The owner revokes them in developer.apple.com → Certificates, Identifiers & Profiles →
   Certificates. Keep every Distribution certificate, and any development certificate a person
   uses on their own Mac (named after the Mac or the person, not "Created via API").
3. Start the TestFlight run again.

If the limit comes back after a run that finished normally, look at that run's "Revoke this run's
development certificate" step. It should list one revoked certificate. If it found none, Xcode put
the certificate somewhere other than the run's keychain, and the step has to look there.

## Tests on the PC

The Mac is shared by every agent, so what does not need Apple's frameworks runs on the owner's
Ubuntu PC (`ssh pc`, 12 cores, WSL) instead:

```sh
scripts/pc-test.sh                         # this worktree, backend and Swift
scripts/pc-test.sh ../other-worktree --backend
scripts/pc-test.sh origin/main --swift     # a git ref, exported with git archive
```

The worktree is rsynced to `~/billet-ci/<name>` (not `.git`, `node_modules`, `.build`, `DerivedData`,
`.env`), so uncommitted changes run, and `node_modules`, the pnpm store (`~/billet-ci/.pnpm-store`)
and `.build` stay between runs. One backend run and one Swift run go at a time on the PC; a second
caller of the same suite waits for the lock. Backend tests keep their temporary files in `/dev/shm`:
on the PC's disk the platform suite took twice as long and one test timed out.

**Backend.** `pnpm install --frozen-lockfile`, `turbo run lint typecheck test`, `format:check`.
Nothing fails on Linux that passes on the Mac; the workerd pool and SQLite behave the same.

**Swift.** Swift 6.4.2, the release of Xcode 27.2's Swift (`.xcode-version`), is unpacked in
`~/swift-toolchains/6.4.2`; `env.sh` there puts it on the `PATH`. It was installed without root:
the tarball from download.swift.org plus `libncurses.so.6` copied into `usr/lib/swift/linux`. The
script runs `check-design.mjs` and its fixture tests, `swift format lint --strict` on every package,
and `swift test --explicit-target-dependency-import-check error -Xswiftc -warnings-as-errors` as
`ios:test` does, in `contracts`, `core`, `pet`, `payments` and `features`.

What builds on Linux is decided in each of those `Package.swift` files, under `#if os(Linux)`: a
Swift file that has an `import` of SwiftUI, UIKit, CoreGraphics, QuartzCore, ImageIO, CoreText,
Security, OSLog, simd, StoreKit, ActivityKit, WidgetKit, AppIntents, AuthenticationServices,
RealityKit or Combine in column 0 is left out, and so are the targets named in the call at the
bottom (`leaveOutAppleOnly`). On the Mac nothing changes. So:

- A file with a guarded import (`#if canImport(SwiftUI)` with the import indented) is built on
  Linux. Use that for the few places where one function needs an Apple API.
- A new file that imports SwiftUI is skipped. If a file that is built needs a type from one that
  is not, the PC run fails with "cannot find ... in scope": move the type into a file that imports
  only Foundation (as `Reaction` and `Swatch` were).
- `Sources/Pet/SimdLinux.swift` stands in for the few `simd_*` functions the cat's geometry uses.
- Not on Linux, for lack of Apple frameworks: the `design` package, `PetScene`, `FeatureCanvas`,
  `FeatureInbox`, `WidgetBridge`, the tests of `DesignSystem`, `Ink`, `FeatureOnboarding`,
  `PaymentsStoreKit`, `PaymentsLive`, the test files that use `URLProtocol`, and `apps/ios`.
  Those run on the Mac or in CI.

