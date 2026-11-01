# billet: plan

A private two-person app for love notes. You draw or send a photo, and it lands on your partner's
widget. Inspired by Noteit, with its own name and visual identity (App Review guideline 4.1 and the
public repo both rule out copying).

## Context

Greenfield project. Stack: SwiftUI + WidgetKit client, and a Cloudflare backend on Effect TS with
Durable Objects, D1 and pnpm. Both sides follow one idea: discriminated unions, explicit state
machines, injected dependencies. The look starts from Memoxia's warm system and shifts romantic.

**Decided with you:** name `billet`; lock screen = widget + Live Activity; free first, paywall after
launch; public repo.


## Answers and constraints that shape the plan

- **Task runner: Turborepo for both languages. No Bazel or moon.** Two native toolchains, about 25
  packages, one developer. Swift joins the graph through a small `package.json` in `packages/ios` and
  `apps/ios` whose scripts call `swift` and `xcodebuild`, with a dependency on fixture generation.
  SwiftPM still does incremental builds: Swift tasks use `outputs: []`, so Turbo only skips unchanged
  tests. A committed `.xcode-version` goes in task inputs because Turbo can't see the installed Xcode.
  `xcodebuild` tasks are Mac-only and stay out of default Linux commands. Bazel's Apple rules would
  replace these tools and add version upkeep. Revisit if CI passes 15 minutes after caching.
- **The TikTok effect can't be reproduced as shown.** I found no public API for setting the
  lock-screen wallpaper. What ships: an editor that looks like the partner's lock screen, a
  lock-screen widget (small and system-tinted), and a colour Live Activity (up to about 160pt tall,
  12 hours maximum on the Lock Screen).
- **App Review risk on the Live Activity.** It is meant for a task with a start and end, so a note
  that stays around may be questioned. Frame it as "a note just arrived" with a real end. The widget
  must stand on its own if this gets rejected.
- **Widget delivery is budgeted, not instant.** Apple: typically 40–70 refreshes a day for a
  frequently viewed widget, and pushes are delivered opportunistically. "Live" drawing exists only
  in the app; the widget updates on send. M1 measures real latency before anything is built on it.
- **Name collision.** "Billet" is already on the App Store (Tu Pana S.A.) and `billet.app` and
  `getbillet.app` are registered. The repo name is free. The store name needs a suffix, such as
  "billet: love notes". `billet.love` shows no nameservers but isn't confirmed available. No
  trademark search has been done.
- **APNs must be tested on a deployed stage.** Deployed Workers reach APNs (Memoxia's `ApnsClient`
  uses this path), but community reports say local `workerd`/`wrangler dev` fails on HTTP/2.
- **Requires:** a paid Apple Developer account, two physical iPhones (WidgetKit push tokens aren't
  issued in the Simulator), and a new Proton Pass vault `Billet`. Also a `Billet Release` vault for
  deploy and store secrets, following Memoxia's split.

## Architecture

```
iPhone A ── WebSocket ──┐                         ┌── APNs ──► iPhone B
iPhone A ── HTTPS ──► Worker ──► PairRoom DO ─────┤            (widget, Live Activity, alert)
                        │        one per couple   └── WebSocket ──► iPhone B (app open)
                        ├──► D1  directory: users, devices, invites, pair lookup
                        └──► R2  note images (private, added to your stack list)
```

- **`PairRoom` Durable Object, one per couple, is the source of truth for that couple.** It holds
  ordered notes, the streak, presence and in-progress strokes in its own SQLite, with hibernatable
  WebSockets. Alarms handle push retries and streak rollover. Deleting a pair means deleting one DO
  plus its R2 prefix.
- **D1 is only the cross-couple directory.** It answers what a DO can't: which pair is this user in,
  and who owns this invite code. Invite claims are transactional.
- **Two renditions of every note.** A compact vector (simplified, quantised strokes, under about
  3 KB) travels inside the push, because Live Activity data is capped at 4 KB and it can't use the
  network. A full PNG goes to R2 for widgets, history and photos.
- **Delivery has layered lanes, each behind one `DeliveryLane` union:** WebSocket when the app is
  open → WidgetKit push (iOS 26+) → alert push with Notification Service Extension writing to the App
  Group → timeline refresh as a catch-up.
- **Auth:** Sign in with Apple, verified in the Worker, then an opaque session token stored hashed in
  D1. Widget and extensions read it from a shared Keychain group.
- **Privacy:** TLS, a private R2 bucket, authorised media routes. End-to-end encryption is
  post-launch. Note that a public repo must never hold user data or `.alchemy` state.

### Swift mirrors Effect without porting it

| Effect | Swift in billet |
| --- | --- |
| `Data.taggedEnum` | `enum` with associated values and exhaustive `switch`, no `default` |
| Typed error channel `E` | Typed throws, `throws(PairingError)` |
| `Context.Service` + `Layer` | Structs of `@Sendable` closures, composed in one `Live` root |
| `R` requirements | Explicit `Dependencies` parameters. No singletons or global container |
| Test layers | Fake service values passed in |
| `Effect` as a description | An `Output` enum returned by a pure transition, run by an interpreter |

```swift
protocol Machine {
  associatedtype State: Sendable
  associatedtype Event: Sendable
  associatedtype Output: Sendable
  static func transition(_ state: State, _ event: Event) -> (State, [Output])
}
```

A small `Store<M: Machine>` (`@Observable`, `@MainActor`) runs outputs through injected services and
feeds results back as events. Illegal states are unrepresentable: each state carries only the data
valid there. Swift 6 strict concurrency stays on. No third-party architecture dependency: this is
about 100 lines, and TCA's macros would slow builds and don't belong in extensions.

The backend uses the same shape. `PairRoom` is a pure `decide(state, command)` reducer that tests
run without `workerd`, wrapped by a thin DO adapter owning a per-object `ManagedRuntime`.

### Keeping TS and Swift in step

Effect Schema in `packages/contracts` is the source of truth. It emits golden JSON fixtures for every
union case. Swift tests decode and re-encode each fixture, and CI fails on drift. Types are written
by hand in Swift: about 25 of them, so this beats maintaining a generator. Revisit if that changes.

## Repository layout

```
apps/
  api/                  Worker entry, composition root only
  ios/                  XcodeGen project.yml; thin App, Widget, NotificationService targets
packages/
  contracts/{domain,http-api,realtime,push,fixtures}
  backend/{platform,auth,pairing,pair-room,notes,push,accounts}
  config/{typescript,oxlint}
  ios/                  One SwiftPM package, many targets:
    BilletKit           Machine, Store
    Domain              Pure types
    Wire                Codable contract types
    Ink                 Strokes, renderer, compact encoding
    DesignSystem        Tokens, components
    Transport           HTTP, WebSocket
    Persistence         App Group, Keychain
    Delivery            Shared by app and notification extension
    Surfaces            Widget and Live Activity views
    Feature*            Onboarding, Pairing, Canvas, Inbox, Settings
```

The SwiftPM graph enforces boundaries at compile time: `Surfaces` can import `Domain`, `Ink` and
`DesignSystem`, and can't import features. TS follows `stash`: kebab-case, no barrels, `exports` as
the only boundary, and only `platform` touches bindings.

**Tooling:** Effect `4.1.1`, exact-pinned in the pnpm catalog. Alchemy `2.0.0-beta.84`, also exact.
Vitest `^4.1`, because `@cloudflare/vitest-pool-workers` 0.23 requires it (`stash` is on 5; re-check
at setup). oxlint, oxfmt, Turborepo. XcodeGen with no committed `.xcodeproj`. swift-format. Node 24.

**Defaults:** iOS 18 minimum, with WidgetKit push gated on iOS 26. Bundle ID `com.mikitahimpel.billet`.
MIT licence. iPhone only at launch. One partner per account.

## Design direction: "candlelight letter"

Start from `docs/DESIGN.md` in Memoxia: quiet premium, warm-only palette, dark-first, one obvious
anchor per screen, ink for primary actions, the 28pt/capsule radius roles, measured contrast, one
gutter, wave seams. Your screenshot's candlelit tone fits this well.

Shift toward romantic:

| Role | Memoxia | billet starting point |
| --- | --- | --- |
| Dark page | `#121010` | `#161011`, wine-black |
| Dark rungs | `#231E18`, `#302822` | `#261A1B`, `#352325` |
| Light page | `#F6F2ED` | `#F8F0EC`, letter paper |
| Ink | `#211D1A` | `#2A1A1C` |
| Cream on fields | `#FBF3E6` | Keep |
| Plate fields | amber, umber, clay | wine `#5E1F2E`, dusk rose `#7A3B46`, ember `#6E2F1E` |
| Reserved colour | coral, mascot only | wax-seal rose `#B8485F`, seal only |

- **Hex values are starting points.** Each must clear Memoxia's floors in a test: 4.5:1 text, 3:1
  marks, visible rungs.
- **Type changes on purpose.** Handwriting moves from secondary aside to the emotional centre, and a
  literary serif (Fraunces or Cormorant, OFL) joins for display only. This reverses Memoxia's
  "no serif" rule.
- **The wax seal replaces the mascot.** It gets the same strict rule: its rose appears only on the
  seal, never as a button or selection colour.
- **Never:** pink gradients, confetti hearts or anything childish. The user's drawing is the
  decoration.
- `docs/design.md` records this in Memoxia's format, including what was rejected and why.

## Tickets

Each becomes a GitHub issue with scope, "done when", and dependencies, under one tracker issue.

### M0: Foundation

| # | Ticket | Needs |
| --- | --- | --- |
| 1 | Bootstrap monorepo: pnpm, Turbo, TS, oxlint, oxfmt, AGENTS.md; Swift task wiring, `.xcode-version`, Mac-only tasks | none |
| 2 | TS CI: lint, typecheck, test, fixture freshness | 1 |
| 3 | iOS shell: XcodeGen, app, widget, notification targets, SwiftPM package, App Group, Keychain group | 1 |
| 4 | iOS CI: path-filtered build, tests, swift-format, fixture conformance | 2, 3 |
| 5 | Alchemy graph: Worker, D1, R2, `PairRoom`; dev and prod stages; deploy workflow; secrets | 1 |
| 6 | `BilletKit`: `Machine`, `Store`, dependency pattern, example with tests | 3 |
| 7 | Contracts: domain schemas and golden fixtures, Swift `Wire` conformance | 2, 4 |
| 8 | Design system: `docs/design.md`, tokens, type, core components, contrast tests | 3 |

### M1: Delivery spike (gate)

| # | Ticket | Needs |
| --- | --- | --- |
| 9 | Throwaway walking skeleton: hardcoded pair, send a drawing, deployed stage | 3, 5 |
| 10 | Port APNs client with `alert`, `widgets`, `liveactivity` push types | 5 |
| 11 | Measure on two iPhones: latency p50/p95 per lane, for locked, force-quit, Low Power and notifications-off, over 7 days | 9, 10 |
| 12 | Live Activity: push-to-start, stroke rendering within 4 KB, App Review position | 9, 10 |
| 13 | Decision record: lane order, compact format, go/no-go on Live Activity | 11, 12 |

### M2: Backend

| # | Ticket | Needs |
| --- | --- | --- |
| 14 | Sign in with Apple, sessions, device and token registry | 7 |
| 15 | Pairing: invite code, transactional claim, unpair | 14 |
| 16 | `PairRoom` reducer and DO adapter, tests in plain Vitest and `workerd` | 7 |
| 17 | Realtime: hibernating WebSocket, stroke relay, presence, reconnect with sequence numbers | 16 |
| 18 | Notes and media: upload, R2, authorised reads, history | 15, 16 |
| 19 | Push lanes: fan-out, alarm retries, dead-token cleanup, idempotency | 10, 13, 16 |
| 20 | Streaks | 16 |
| 21 | Account deletion, Apple token revocation, DO and R2 purge | 15, 18 |
| 22 | Rate limits, structured logs, block and report endpoints | 15 |

### M3: iOS app

| # | Ticket | Needs |
| --- | --- | --- |
| 23 | `Ink`: stroke model, Metal or Canvas renderer, undo/redo, compact encoding | 6 |
| 24 | Transport and Persistence: HTTP, WebSocket state machine, App Group, Keychain | 6, 7 |
| 25 | Onboarding and sign-in | 8, 14, 24 |
| 26 | Pairing flow | 15, 25 |
| 27 | Canvas: lock-screen-style editor, tools, background photo, send | 23, 24 |
| 28 | Live co-drawing | 17, 27 |
| 29 | Inbox and history, streak display | 18, 24 |
| 30 | Settings, unpair, delete account, block, report, delivery health check | 21, 22, 26 |

### M4: Surfaces

| # | Ticket | Needs |
| --- | --- | --- |
| 31 | Home-screen widgets: small, medium, large; correct downsampling; empty and unpaired states | 18, 23 |
| 32 | Lock-screen widgets: rectangular, circular, inline | 31 |
| 33 | Notification extension and the shipping delivery pipeline | 13, 19, 31 |
| 34 | Live Activity and Dynamic Island, if #13 says go | 13, 33 |

### M5: Launch

| # | Ticket | Needs |
| --- | --- | --- |
| 35 | App name, icon, wax-seal mark, domain, trademark check | 8 |
| 36 | Privacy policy, terms, privacy manifest, nutrition labels | 21 |
| 37 | Fastlane and TestFlight pipeline | 4 |
| 38 | Crash and delivery monitoring | 19, 33 |
| 39 | Private beta with real couples | 34, 36, 37, 38 |
| 40 | Store screenshots, listing, App Review submission | 35, 39 |

### Post-launch (filed as backlog)

Subscriptions and gifting, streak repair, end-to-end encryption, more brushes and fill, Android.

## What to reuse

- `memoxia-current-design/apps/server/src/modules/notifications/apns-client.ts` and `apns-jwt`:
  Effect APNs client with token caching and failure classification. Extend beyond `alert`.
- `memoxia-current-design/apps/server/src/tutor-agent.ts`: per-DO `ManagedRuntime` at the edge.
- `memoxia-current-design/apps/server/AGENTS.md`: Layer composition rules.
- `memoxia-current-design/.github/workflows/ci.yml`: TS CI shape and optional self-hosted runner.
- `memoxia-current-design/apps/native/lib/ui/utils/color-ramp.ts`: Oklab ramps, to port for plates.
- `stash`: `alchemy.run.ts`, `alchemy-d1-state.ts`, `docs/alchemy.md`, repo conventions.

Memoxia's licence should be confirmed before copying code into a public repo. You own it, but check
that nothing private travels with it.

## Verification

- **Of this step:** `gh issue list --repo mikitahimpel/billet --limit 60` shows every ticket in the
  right milestone; the tracker links resolve; `git grep` finds no secrets or personal data.
- **Of the project:** the end-to-end test is on two real iPhones, on a deployed stage. Draw on A and
  it appears on B's home-screen widget while locked, with latency under the target set in #13. Then
  delete the account and confirm the DO, R2 objects and D1 rows are gone.
