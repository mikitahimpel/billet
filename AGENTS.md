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
pnpm turbo run ios:format:check    # swift-format, packages only
pnpm turbo run ios:generate        # apps/ios/Billet.xcodeproj
xcodebuild test -project apps/ios/Billet.xcodeproj -scheme Billet \
  -destination 'platform=iOS Simulator,name=<iPhone>' CODE_SIGNING_ALLOWED=NO
```

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
