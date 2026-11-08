# Release inventory: experiments, flags and test paths

App Review guideline 2.5.19 forbids experimental or unfinished features in the shipped app (issue
#99). This is every experiment, flag and test path in the app and on the server, with what to do
about it before the first release. "Owner" means a product choice that this page does not make.

## Server flags (`registry`, `packages/backend/flags/src/experiments.ts`)

All are `draft`: no pair gets a variant unless the owner starts one or overrides a pair. Delivered
by `GET /v1/flags`; a variant the app lacks is ignored.

| Key | Kind | Default | Release |
| --- | --- | --- | --- |
| `payments` | flag | `off` | **Keep, fixed `off`.** No coin purchases in the first release. Never start it before payments ship (`docs/payments.md`). |
| `pick-tonight` | flag | `on` | **Keep as a kill switch, fixed `on`.** It is a shipped feature with a safe off. |
| `rooms` | experiment | `both` | **Owner.** Room vs City vs both. Until decided, leave it `draft` so every pair gets `both`. |
| `home-layout` | flag | `classic` | **Owner.** Home variants (`immersive`, `living-window`, `night-and-day`). Leave `classic` until chosen. |
| `room-lighting` | flag | `amber-lantern` | **Owner.** Room lighting variants. |
| `window-view` | flag | `suburb-night` | **Owner.** Window views. |

Each of the four owner flags is read by the app (`WidgetFeatures`, `RemoteFlags.Experiments`), so
none is dead. When the owner picks, the loser variants go: remove them from the registry and the
Swift choices in one PR, so the app never ships a variant it cannot show.

## App: screens and settings that ship

- **Settings > Labs** (`SettingsView.swift`) is in every build; hiding it and account deletion come with #502. It holds:
  - *Cat brain* and *Cat brain card* (owner: the brain is the cat's behaviour, the card is a
    debug view of it, so the card should not ship);
  - *Show all hints now* (a testing tool: remove from release or hide behind `#if DEBUG`);
  - *Style* (`StyleGallery`, owner: the style variants);
  - *Rooms* (a per-phone override of the `rooms` experiment, owner with the flag).
  Recommendation: ship Labs only in debug and TestFlight-internal builds, and have the release
  build use the owner's chosen fixed values. Hidden settings are still shipped code, so removing
  the section is better than hiding it.
- **Settings > Testing** (`Pair with a demo partner`) only appears when the server answers the
  demo partner route. Only the dev stage mounts those routes, so prod never shows it. Keep, but
  see "App Review" for how the reviewer pairs.
- **Onboarding > "Try with a demo partner"** is the same dev-server path. Same answer.

## App: compiled out of Release (`#if DEBUG`)

Not in a release build; listed so nobody counts them. Launch arguments for screenshots:
`shotMoments`, `shotMoment`, `onboardingOpen`, `catCoat`, `inboxFixture` (`InboxFixture.swift`),
`hint`, `uitestNoHints`, `tab`, `shopItem`, `shopSet`, and `ShopFixture`. Push tokens register
for the APNs sandbox in Debug and for production otherwise (`DrawingSync.swift`).

## App: reachable in a release build

- **`-perf.script` launch argument** (`NookiPerf.swift`, `ScenePerf`): starts a frame recorder
  and a script that drives the room. It needs a launch argument, so users and reviewers never
  trigger it, but it is test code in the binary. **`-perf.script` must be compiled out of Release** (#515: it touches the app and `packages/ios/pet`, and the perf CI measures Release builds, so it is not a small change).
- **Mock store.** `BILLET_PAYMENTS` defaults to `mock`: the mock store credits coins without
  money and shows a Labs payments view. **A release build must be made with
  `BILLET_PAYMENTS=storekit`**, or the shop sells fake coins. Add this to the upload check (#37).
- **`XCTestConfigurationFilePath`** in `NookiApp.swift` only detects a test host; no behaviour
  for users.

## Server: test paths

- **Demo partner routes** (`packages/backend/demo-partner`): mounted only when
  `settingsForStage(stage).devTools` is true, which is the `dev` stage only. Keep.
- **Demo rooms** (`DemoRoom`, `/demo`, `packages/backend/platform/src/demo-*`): the old test-room
  service. Bound only on the `dev` stage in `alchemy.run.ts`, and nothing in `apps/ios` or
  `packages/ios` calls it. **Remove before release**, in its own backend PR: deleting a Durable
  Object class needs a `deleted_classes` migration and a deploy, and `docs/privacy.md` has a
  "Test rooms" paragraph to delete with it. Not done here.
- **Payments dev tools** (Xcode transactions, mock purchases): dev stage only. Keep.

## Removed in this PR

Nothing. Every client flag above is read by the app, so none is dead, and the dead server
test path (demo rooms) needs a migration and a deploy that this docs PR must not carry.

## A release check (#37)

Fail the upload when any of these is true:

1. The build was not made with `BILLET_PAYMENTS=storekit`.
2. The Labs section or `NookiPerf` is still compiled into Release.
3. `registry` has a flag whose status is `running` or whose `default` differs from the table
   above.
