# TestFlight from GitHub Actions

`.github/workflows/testflight.yml` archives the app on a GitHub macOS runner, checks the archive and
uploads it to TestFlight. It only runs when started by hand, and each run waits for the repository
owner's approval before it can read any secret.

## Running it

```sh
gh workflow run testflight.yml --ref main
gh workflow run testflight.yml --ref main -f build=17   # a particular build number
gh run watch "$(gh run list --workflow testflight.yml --limit 1 --json databaseId -q '.[0].databaseId')"
```

Approve the run on its page (Review deployments → testflight), or with
`gh api -X POST repos/mikitahimpel/billet/actions/runs/<run-id>/pending_deployments -F 'environment_ids[]=<id>' -f state=approved -f comment=ok`.

The run ends by printing one line, `build <number>: <processing state>`, also shown in the run
summary. `VALID` means testers can install it. `PROCESSING` means App Store Connect has the build and
is still working on it, which can take up to half an hour after the run ends.

## What it does

1. Fails straight away, naming them, if any of the four secrets is missing.
2. Writes the App Store Connect key to a file only the runner user can read (mode 0600). The last
   step deletes it, along with the run's keychain, even when an earlier step failed.
3. Picks the build number: one above the highest build App Store Connect has for the app, and at
   least 16, since the local archives went up to 15. A number given with `-f build=N` is used
   instead, and the run stops if App Store Connect already has that build or a later one. The version
   stays 0.1.0 (`MARKETING_VERSION` in `apps/ios/project.yml`).
4. Generates the project with XcodeGen and archives Release with automatic signing:
   `xcodebuild archive -allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …`.
   The bundle IDs, team 2666YPBJTB and signing setup are the project's own, unchanged.
5. Runs `apps/ios/scripts/testflight/check-archive.sh` on the archive. That script checks:
   - the bundle IDs, version and build of the app, widget and notification service;
   - `codesign --verify` and the team on all three;
   - that nothing from Rive is in the app;
   - that every cat file is in the bundle;
   - that the demo host is the app's `BilletDemoHost` and appears nowhere in git history.
6. Exports with `apps/ios/ExportOptions-external.plist` (`method` app-store-connect,
   `destination` upload, `uploadSymbols` on), which signs with a cloud-managed Apple Distribution
   certificate and uploads the build to TestFlight.

Nothing is exported from a Mac's keychain. The archive is signed with an Apple Development
certificate that Xcode creates through the API key. Distribution signing happens in Apple's cloud
when the archive is exported.

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

Each run may leave an Apple Development certificate named "Created via API" in the developer
account. When the account nears its certificate limit, revoke the old ones under Certificates,
Identifiers & Profiles. They only signed CI archives, so revoking them changes nothing for
TestFlight builds.
