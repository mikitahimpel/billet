# Architecture

This document explains how billet is put together and why. It is written for someone new to the
project. For scope, milestones and open questions, see [plan.md](plan.md).

## What the system does

Two people are paired. One draws a note or sends a photo. The other sees it on their iPhone widget,
and sometimes as a Live Activity or a notification. Everything else in the design serves that path.

## System overview

```
iPhone A ── WebSocket ──┐                         ┌── APNs ──► iPhone B
iPhone A ── HTTPS ──► Worker ──► PairRoom DO ─────┤            (widget, Live Activity, alert)
                        │        one per couple   └── WebSocket ──► iPhone B (app open)
                        ├──► D1  directory: users, devices, invites, pair lookup
                        └──► R2  note images (private bucket)
```

### PairRoom: one Durable Object per couple

The `PairRoom` Durable Object is the source of truth for one couple. It stores the ordered notes, the
streak, presence and the couple's cat (its profile, temper and append-only journal, see
[cat-state.md](cat-state.md)) in its own SQLite database, relays in-progress strokes, and uses hibernatable
WebSockets so idle rooms cost nothing. Alarms handle push retries and streak rollover. Deleting a
couple means deleting one Durable Object and its R2 prefix.

Live drawing on the shared canvas streams over the room's socket: `StrokeBegin`, then
`StrokePoints` batches (at most 64 points, sent every 30 to 50 ms), then `StrokeEnd`, plus `Clear`
for both partners. The room relays these to the partner and does not store them. It remembers
which strokes each socket has open on the socket's attachment, so when a phone leaves mid-stroke
the partner gets `StrokeDropped` for each. Each socket may send 60 frames a second; the room drops
the rest.

### D1: the cross-couple directory

D1 holds only what a single `PairRoom` cannot know: users, their devices and sessions, which pair a
user belongs to, and who owns a given invite code. Claiming an invite is transactional.

D1 has no interactive transactions. An operation that spans statements runs as one D1 batch, through
`D1Client.batch`, so a later statement reads earlier results in SQL rather than in JavaScript.

### Database access: Drizzle on the official Effect drivers

Decision: `packages/backend/platform` uses Drizzle through `drizzle-orm/effect-d1` (on
`@effect/sql-d1`) and `drizzle-orm/effect-sqlite-do` (on `@effect/sql-sqlite-do`). We write no custom
Effect wrapper. Alchemy generates and applies D1 migrations. On Durable Object SQLite,
`openRoomDatabase` applies them with the drizzle migrator when an object activates. `PairRoom` moves
to it in #67.

- `drizzle-orm` and `drizzle-kit` are pinned to `1.0.0-rc.5-ab785fc`, a release candidate and not a
  stable release.
- This is the fallback from the first design, which used `Drizzle.DurableObject` and
  `Cloudflare.SqlMigrations`. They need an Effect-native Durable Object, which crashes the Alchemy CLI
  on effect 4.1, so the Worker stays free of Alchemy. See [alchemy.md](alchemy.md#drizzle), which also
  covers how migration files are generated and what a failed migration does.
- Effect Schema stays the domain and wire types. `drizzle-orm/effect-schema` only derives schemas from
  tables, and the domain is hand-written with brands and tagged unions, so it cannot generate them. A
  test derives each table's schema instead, and fails if a column's name, type or nullability differs
  from the domain type. The test fails on any exported table it does not list, so a new table needs
  its domain type added to `test/schema-drift.test.ts`. Other tests apply the migrations to an empty
  database and compare `PRAGMA table_info` with each table's columns.

### R2: note images

Images live in a private R2 bucket, each couple's under `pairs/<pairId>/`. Media routes check
authorisation before serving anything.

### Two renditions of every note

- A compact vector form (simplified, quantised strokes, under about 3 KB) travels inside the push
  notification. Live Activity data is capped at 4 KB and cannot use the network, so it has to fit.
- A full PNG goes to R2 and is used by widgets, history and photos.

### Delivery lanes

Delivery is layered. Each lane is a case of one `DeliveryLane` union:

1. WebSocket, when the app is open.
2. WidgetKit push (iOS 26 and later).
3. Alert push, with a Notification Service Extension writing to the App Group.
4. Timeline refresh, as a catch-up.

Widget delivery is budgeted by the system, not instant. Apple typically allows 40 to 70 refreshes a
day for a frequently viewed widget, and pushes arrive opportunistically. Live drawing exists only
inside the app; the widget updates when a note is sent. The first milestone measures real latency
before anything is built on it.

### Authentication

Every user starts anonymous: the app opens an account on first launch with no prompt. Sign in with
Apple only links that account later, so it can be recovered without the phone. Sessions are opaque
bearer tokens, stored hashed in D1. The widget and extensions read the token from a shared Keychain
group.

1. On first launch the app makes an account key (32 random bytes) and keeps it in the iCloud
   Keychain, so the user's other and future phones have it too. It posts the key
   (`POST /v1/auth/anonymous`). The server keeps only the key's SHA-256: a key it hasn't seen opens a
   new anonymous user, and one it has seen signs in to the user it opened.
2. To link Apple, the app asks for a challenge (`POST /v1/auth/challenge`). The server stores only
   the nonce's hash, for 10 minutes, and the app passes the nonce to Apple unchanged.
3. The app posts the identity token with its session (`POST /v1/auth/apple/link`). The Worker checks
   the RS256 signature against Apple's keys, then `iss`, `aud`, `exp`, `sub` and `nonce`, and
   deletes the nonce, so each token is used once. The user, the pair, the cat and the notes stay as
   they are. An Apple ID already linked to another account is refused (409 `AppleIdInUse`).
4. A phone with neither the key nor a session signs in with Apple instead (`POST /v1/auth/apple`),
   which lands in the linked account. The Apple `sub` is stored; email, name and Apple's tokens are
   not.
5. Every sign-in returns a new session on a new device. The server keeps only the token's SHA-256,
   and sessions last 90 days from the last use (`GET /v1/account` says whether Apple is linked).
6. The device registers one push token per kind (`PUT /v1/devices/current/push-token`), which replaces
   the last one. A token moves to whichever device registered it last, and sign-out deletes the
   device and its tokens, so a phone never receives another account's notes.

Failures are uniform: any rejection is a 401, and if Apple's keys or the database can't be read the
answer is a 503. Nothing is granted on a failure, and an expired key set is never used. Logs carry
fixed reason labels only.

`packages/backend/auth` holds this logic on injected services: `IdentityVerifier`, `AuthRepository`
(challenges, account keys, push tokens) and `AuthEngine` (users, sessions and linked identities).
`platform` provides the real ones. `AuthEngine` is [Better Auth](https://www.better-auth.com) on D1
through Kysely, with its anonymous and bearer plugins and the Apple provider; its HTTP handler is
never mounted, so every request goes through the typed routes above. Better Auth keeps session
tokens as they are, so `hashed-session-tokens.ts` wraps its database adapter to keep their SHA-256
instead. `respondApi` serves the routes under `/v1/`.

`respondApi` builds the router for each request, because a Worker request must not wait on I/O that
another request started, and `Jwks` shares its in-flight fetch between callers. So Apple's keys are
cached by Cloudflare, in the key fetch itself, for 10 minutes. Only successful responses are cached.

### Pairing

A user asks for an invite (`POST /v1/invites`), sends the code to their partner, and the partner claims
it (`POST /v1/invites/claim`), which returns the new pair's id. Either partner can end it
(`DELETE /v1/pair`). Pairing keeps two tables in D1:

- `invites` says who owns a code. A code is 10 symbols from a 32-symbol alphabet with no `0`, `O`, `1`
  or `I`: 50 random bits. Only its SHA-256 is stored, and it lasts 24 hours. A user has one invite, so
  a new one replaces the last, and saving an invite also removes every expired one.
- `pair_members` is the pair lookup, one row per user. Its key is the user, so one partner per account
  holds even if the code is wrong. A pair is the two rows that share a `pair_id`.

A claim is one D1 batch. The first statement adds the claimer only if the invite is live, belongs to
someone else, and neither user has a partner. The next adds the owner only if the first wrote a row,
and the next deletes both users' invites. Batches run one at a time, so the claim that comes second
finds no invite and gets `InvalidInvite`. A last statement reads the claimer's row to tell the outcomes
apart.

Failures are `InvalidInvite` (404) for any code that can't be claimed, with no hint why, and
`AlreadyPaired` (409) for a caller with a partner. Unpair removes both rows, and succeeds for a user
with no partner so that a client can retry it. Pairing again gives a new `pair_id`, so a new room.

`packages/backend/pairing` holds this logic on an injected `PairingRepository`, which `platform`
provides.

### Notes and media

A note is sent in two steps, and both need a session and a partner:

1. `POST /v1/media` takes the PNG as the raw body, up to 10 MiB, and returns its `image` key,
   `pairs/<pairId>/notes/<uuid>.png`. Bytes without the PNG signature are refused.
2. `POST /v1/notes` takes `SendNoteRequest`, naming that key. For a drawing it also carries the compact
   rendition, at most 3072 bytes of JSON, the budget of the iOS encoder. The image must exist under the
   couple's prefix.

`GET /v1/media/<key>` serves an image, with `cache-control: no-store`. `GET /v1/notes` returns notes
oldest first, from `PairRoom`. `after` is the last `seq` the client holds, default 0, and `limit` is
1 to 100, default 100. Sequences have no gaps, so the next page starts at `after` plus the notes
returned.

Every request starts from the pair D1 says the caller is in, never from one the client names: the
room is the one named after that pair, and a key is only read if it starts with that pair's prefix.
Anyone else gets the 404 of a key that doesn't exist, so a response never shows that an image exists,
and the bucket isn't read. Unpairing ends access for both partners, and pairing again gives a new
prefix and room.

Pairing commits in D1 and doesn't reach the room, so the first note opens it, with the members from D1.
A repeated open is accepted, so two first notes at once are safe.

`packages/backend/notes` holds this logic on injected `MediaStore` and `PairRooms` services, which
`platform` provides. The cat routes (`GET`/`PUT /v1/cat`, `GET /v1/cat/journal`,
`POST /v1/cat/events`) live there too, in `CatService`, on the same rule: the pair comes from D1.

### Deleting an account

`DELETE /v1/account` deletes the caller's account and everything it owns, as App Store guideline
5.1.1(v) asks. The body is `DeleteAccountRequest`; a linked account sends the authorization code of
a fresh Sign in with Apple in it. In order:

1. With a code, the Worker trades it at Apple's `/auth/token` for a refresh token and revokes that at
   `/auth/revoke`, with a client secret signed by the Sign in with Apple key (`APPLE_SIGN_IN_KEY`).
   The outcome is logged as a label; a failure or a missing key never stops the deletion.
2. In every room the user has been in (the current pair, and each pair `pair_events` names), the
   `PairRoom` deletes the notes they sent and the cat with its whole journal, and closes its
   sockets, and their images go from R2: the
   ones those notes name, and every image under the prefix whose `uploader` metadata is theirs.
3. One D1 batch ends the pair, leaves the partner a `partner_notices` row, and deletes the user's
   `users` and `auth_user` rows with their sessions, Apple link, account key, devices, push tokens,
   invite and counted events.
4. One more pass over the current room catches a note sent while the batch ran.

A failure before step 3 answers 503 and leaves the account, so the app tries again; nothing deleted
comes back. Afterwards the old session is unauthorized, which is also the answer to a retry.

The partner keeps the cat, their own notes and their account. They are unpaired, and
`GET /v1/account` returns `partnerLeft` while they stay unpaired, so the app can tell them gently;
pairing again clears it. Analytics Engine points hold no user id, only the pair hash, so nothing
there names the user. `packages/backend/account` holds this logic on an injected
`AccountRepository` and `AppleTokenRevoker`, which `platform` provides.

### Privacy

Traffic uses TLS, the R2 bucket is private, and media routes are authorised. End-to-end encryption is
planned after launch. A public repository must never contain user data or `.alchemy` state.

## One idea on both sides

Both the Swift client and the TypeScript backend follow the same pattern: discriminated unions,
explicit state machines, and injected dependencies. Swift mirrors Effect's ideas without porting the
library.

| Effect | Swift in billet |
| --- | --- |
| `Data.taggedEnum` | `enum` with associated values and an exhaustive `switch`, no `default` |
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
feeds the results back as events. Illegal states are unrepresentable: each state carries only the data
that is valid there. Swift 6 strict concurrency stays on. There is no third-party architecture
dependency; the pattern is about 100 lines, and TCA's macros would slow builds and do not belong in
app extensions.

The backend uses the same shape. `PairRoom` is a pure `decide(state, command)` reducer that tests run
without `workerd`, wrapped by a thin Durable Object adapter that owns a per-object `ManagedRuntime`.

## Keeping TypeScript and Swift in step

Effect Schema in `packages/contracts` is the source of truth. It emits golden JSON fixtures for every
case of every union. Swift tests decode and re-encode each fixture, and CI fails if the two sides
drift. The Swift types are written by hand: there are about 25, so this is cheaper than maintaining a
code generator. Revisit that if the number grows.

## Repository layout

```
apps/
  api/                  Worker entry, composition root only
  ios/                  XcodeGen project.yml; thin App, Widget, NotificationService targets
packages/
  contracts/{domain,http-api,realtime,push,fixtures}
  backend/{platform,auth,account,pairing,pair-room,notes,flags,metrics,admin,payments}
  config/{typescript,oxlint}
  ios/                  SwiftPM packages, one per layer:
    contracts/          BilletContracts
      Domain            Pure types
      Wire              Codable contract types, tested against packages/contracts/fixtures
    core/               BilletCore
      BilletKit         Machine, Store
      DesignSystem      Tokens, components
      Ink               Strokes, renderer, compact encoding
      Transport         HTTP, WebSocket
      Persistence       App Group, Keychain
      Delivery          Shared by app and notification extension
    payments/           BilletPayments
      Payments          The protocol and stamp packs
      PaymentsMock, PaymentsStoreKit, PaymentsLive (picks one by BILLET_PAYMENTS)
    pet/                BilletPet
      Pet               World state and the delivery scenario, no graphics
      PetScene          The contract between the pet and a scene
      PetSceneCatalog   The linked scenes and the user's choice
    features/           BilletFeatures
      Feature*          Home, Onboarding, Pairing, Canvas, Inbox, Settings
      Surfaces          Widget and Live Activity views
      WidgetBridge      Flags, snapshot and queue shared by app, widget and settings
      Labs              Experiments
    scripts/            The import check every package runs before build and test
  pet-scenes/reality  The RealityKit scene, the only one the app ships
```

### Swift package layers

Each layer is its own package, so it builds and tests alone (`swift test` in its folder) and an
agent working in one layer does not rebuild the others' tests. Dependencies only point down:

```
features ──► pet ──► core ──► contracts
   │                  ▲          ▲
   ├──────────────────┘          │
   ├─────────────────────────────┘
   └──► payments   (depends on nothing)

pet-scenes/reality ──► pet, core
```

`WidgetBridge` sits in `features`, not `core`, because it uses `Pet`. Target and product names are
the same as when this was one package, so imports name modules, not packages. The apps add each
package they link in `project.yml`.

### Pet scenes

The App target lists the scenes it ships, and removing one means not linking its package. Graphics
engines stay inside `packages/pet-scenes`; `ios:test` fails if any package in `packages/ios` imports
RealityKit or Rive.
Scenes show `PetWorld` and report events, and `Pet` finishes a step by deadline if a scene hangs.
The widget links no engine: the catalog copies the chosen scene's PNG poses to the App Group.

The SwiftPM dependency graph enforces boundaries at compile time. For example, `Surfaces` may import
`Domain`, `Ink` and `DesignSystem`, but not any feature target.

On the TypeScript side: kebab-case file names, no barrel files, `exports` in `package.json` as the
only module boundary, and only the `platform` package touches Cloudflare bindings.

The Xcode project is generated by XcodeGen, so no `.xcodeproj` is committed.

## Task runner: Turborepo for both languages

Decision: use Turborepo for TypeScript and Swift. Do not use Bazel or moon.

Reasoning:

- There are two native toolchains, roughly 25 packages and one developer. A heavier build system
  would cost more to maintain than it saves.
- Swift joins the Turbo graph through a small `package.json` in each `packages/ios/<layer>` and in
  `apps/ios`. Its scripts call `swift` and `xcodebuild`, and depend on fixture generation. A layer's
  `package.json` lists the layers it builds against, so a change below reruns the layers above.
- SwiftPM already builds incrementally. Swift tasks therefore declare `outputs: []`, so Turbo only
  skips tests whose inputs have not changed.
- A committed `.xcode-version` file is listed in task inputs, because Turbo cannot see which Xcode is
  installed.
- `xcodebuild` tasks only run on a Mac, so they are kept out of the default commands that run on
  Linux.
- Bazel's Apple rules would replace the standard Apple tools and add version upkeep.

Revisit this if CI takes more than 15 minutes after caching.

## Tooling

Effect `4.1.1`, Alchemy `2.0.0-beta.84` and `drizzle-orm` `1.0.0-rc.5-ab785fc` are pinned exactly.
Vitest is `^4.1`, because
`@cloudflare/vitest-pool-workers` 0.23 requires it. The rest of the toolchain is oxlint, oxfmt,
Turborepo, XcodeGen, swift-format and Node 24.

## Testing note: push notifications

APNs must be tested on a deployed stage. Deployed Workers can reach APNs, but local
`workerd`/`wrangler dev` has reported HTTP/2 failures. Widget push tokens are also not issued in the
iOS Simulator, so delivery testing needs two physical iPhones.
