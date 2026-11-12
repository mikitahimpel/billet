# AGENTS.md

billet: a two-person iPhone app. The app is `apps/ios` (Ourio), the backend is
Cloudflare Workers on Effect. Architecture: [docs/architecture.md](docs/architecture.md). Current
work: GitHub issues, tracker #46.

## Layout

| Path | What |
| --- | --- |
| `apps/ios` | App, widgets, notification and share extensions. XcodeGen (`project.yml`). |
| `apps/api` | Worker entry. |
| `packages/ios/<layer>` | Swift packages: `contracts`, `core`, `design`, `pet`, `features`, `payments`. |
| `packages/backend/<context>` | Backend contexts and `platform`. |
| `packages/contracts/<name>` | Effect Schema, source of truth for TS and Swift. |

App look: [docs/design-system.md](docs/design-system.md), the `design` package (`packages/ios/design`). Read it
before any UI work; no raw colours or fonts in feature code.
Images for docs and mockups live in `docs/images/<topic>/` as WebP; app images stay in their bundle.

## Commands

```sh
pnpm install
pnpm turbo run lint typecheck test # TypeScript
pnpm format:check                  # oxfmt: TS, JSON, YAML, HTML, CSS; not Markdown
pnpm alchemy dev                   # local backend (docs/alchemy.md)
pnpm db:generate                   # Drizzle migrations
pnpm ios:test                      # Swift packages (Mac)
pnpm ios:build                     # Swift packages (Mac)
scripts/verify-ios.sh              # what the PR's iOS run checks, on this Mac (--packages, --app)
pnpm turbo run ios:format:check    # swift-format, packages only
pnpm turbo run ios:generate        # apps/ios/Billet.xcodeproj
xcodebuild test -project apps/ios/Billet.xcodeproj -scheme Billet \
  -destination 'platform=iOS Simulator,name=<iPhone>' CODE_SIGNING_ALLOWED=NO
```

Debug builds in every worktree share one compilation cache, `~/Library/Caches/billet-compilation-cache`
(project.yml); a build that fails for no reason in the code is retried after deleting it. When Warmbuild runs on
this Mac (`~/.warmbuild/bin/warmbuild status`), builds read what CI compiled on main: pass
`XCODE_XCCONFIG_FILE=~/.warmbuild/warmbuild.xcconfig` to `xcodebuild` (`scripts/verify-ios.sh` does it). Keep
`-derivedDataPath` under `~/Library/Caches/<name>`, never under `/tmp`: Swift keys from there never match CI's.

`<iPhone>`: any from `xcrun simctl list devices available`. Swift scripts are named `ios:*`, never
`test` or `build`, so the TypeScript commands skip them on Linux.

An app change is also checked by eye in a Simulator. The app reaches a server only when built
with `BILLET_API_HOST`.

## CI

macOS runners are few and shared by every agent.

- The pull request's own `iOS` run is the check. Don't `gh workflow run ios.yml` for a full run;
  a dispatch takes about an hour and holds a runner from everyone else.
- UI tests (`OurioUITests`) run on main only, and some skip on GitHub Actions. Run the ones your
  change can reach locally with `-only-testing:OurioUITests/<Class>`.
- Before you debug a red run, compare it with the latest `iOS` run on main
  (`gh run list --workflow ios.yml --branch main`). A test that fails there with the same error
  isn't yours: report it, don't rerun.

## Run on the pc

The backend suites and the Swift packages that build on Linux run on the owner's PC, not the Mac, and
need no build lock:

```sh
scripts/pc-test.sh [<worktree>|<git-ref>] [--backend|--swift|--all]
```

It rsyncs the worktree to `ssh pc`, streams the output and exits non-zero on a failure. `--backend`
is install, lint, typecheck, test and `format:check` (about 2 minutes; the platform suite does not
time out there). `--swift` is the design rules, swift-format and `swift test` of `contracts`, `core`,
`pet`, `payments` and `features` without the files that import SwiftUI, CoreGraphics or another
Apple framework (the pet's 404 tests in under a minute). Anything in the app, `design`, a View or
RealityKit still needs the Mac or CI. Write new brain, model and store code so it imports only
Foundation, and keep it out of files that import SwiftUI
([docs/testflight-ci.md](docs/testflight-ci.md#tests-on-the-pc)).

## Boundaries

- kebab-case for folders and TS/config files; Swift files are PascalCase after their main type.
- No barrels (`index.ts` re-exports). No cross-package relative imports; use `exports`.
- Only `packages/<context>/platform` touches Worker bindings or runtime globals.
- Versions come from the `pnpm-workspace.yaml` catalog (`"catalog:"`).

## Swift

- `switch` over the project's own enums is exhaustive, no `default`.
- Typed throws (`throws(PairingError)`).
- Explicit dependencies. No singletons or global containers.
- Swift 6 strict concurrency.
- `packages/`: `.swift-format`, 2 spaces, 100 columns. `apps/ios`: 4 spaces, up to 120, match
  the file.
- One module per feature: `Feature<X>` and `<X>Interface` targets in `packages/ios/features`.
  A feature imports another only through its `*Interface`; the app target composes them
  ([docs/ios-architecture.md](docs/ios-architecture.md)).
- Screen and flow state is an `enum` with associated values, changed only through a `Machine`'s
  `send(event)`; no `isLoading` + `error` + `items`, no optional that means a mode. The transition
  table is tested, rejected events included.
- Stores take every dependency in `init`; views get other features as protocols. No
  `UserDefaults.standard`, `NotificationCenter`, `SharedFile` or `CatProfile` in a feature.
- Code the app and its extensions share is in the `*Interface` targets; `apps/ios/Shared` holds only
  the images and the map they bundle ([docs/ios-architecture.md](docs/ios-architecture.md) §1.1.1).
- The Room (`apps/ios/Nooki/Room`) is sealed: `RoomHost(input:)` with `.equatable()`, commands
  through `RoomControlling`, events out through `RoomEvent`. No scene type is named outside it,
  and no scene tick reaches state outside it.
- A horizontal drag on Home never switches rooms; only the explicit control does (`RoomSwipeTests`).

## Comments

- Only where names and types can't say it: why, an invariant, a unit, a side effect, a failure,
  an outside rule.
- Most declarations have none. No doc comment that repeats the name.
- Never about the change or its author: no "added", "now", "fixed", "as requested", no agent or
  model names, no dead code.
- Don't touch comments in code you aren't changing.

## Git

- Branch `<type>/<name>` off `main`, PR, squash-merge. Never push to `main`.
- Merge with `scripts/merge-pr.sh <number>`: it waits for green checks and squash-merges. A branch
  behind `main` merges as it is when `main`'s new commits are in areas it doesn't depend on;
  otherwise the script merges `main` into it and waits again.
- Conventional Commits with scope: `feat(ios): ...`, `fix(activity): ...`.

## Secrets and admin data

- Secrets in Proton Pass; commit only `pass://` references in `.env.pass`, run with
  `pp run --env-file .env.pass -- <command>`.
- Admin data, read-only: `PROTON_PASS_AGENT_REASON="<why>" pp run --env-file .env.pass.agents --
  scripts/admin-read.sh <route>` ([docs/admin.md](docs/admin.md#agent-api)). Never change Access
  credentials.

## Never

`--no-verify`, `eslint-disable`, `@ts-ignore`, `@ts-expect-error`, loosened compiler options. Fix
the cause.
