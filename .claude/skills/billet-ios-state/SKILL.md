---
name: billet-ios-state
description: Use for any Swift state or store work in apps/ios or packages/ios - a store, @Observable, Machine, HomeState, a feature module or its interface, navigation state, sheets, loading or error state, or the Room/scene boundary (RoomHost, CatRoom, DioramaView). Points to docs/ios-architecture.md and its rules.
---

# Billet iOS state

Before adding or changing state, a store, a feature module or anything that touches the room:

1. Read `docs/ios-architecture.md`. Sections 1–4 are the rules, 4.2 is the worked example
   (Coins and Shop), 5 is the Room, 8 is where each feature is in the migration.
2. Find the feature's module. Feature code lives in `packages/ios/features` as `Feature<X>`
   (store, machine, views, tests) and `<X>Interface` (value types, protocols). What is not moved
   yet is in `apps/ios/Nooki` (see the table in 8.2); don't add to `HomeState`, add to the
   feature's store, and if the feature has none yet, say so to the manager before building on
   `HomeState`.

## State

- State is one `enum` with associated values per screen or flow. Each case carries only what is
  valid in it. No `isLoading` + `error` + `items`; no optional that means a mode; items with
  their own lifecycle carry a `Stage` enum.
- It changes only through `Store<M>.send(event)` with a pure `Machine.transition`. Views send
  events, never assign state; a sheet's `isPresented` is a `Binding` whose setter sends an event.
- Effects are `Output` cases run by the store's interpreter; the machine never awaits. Time is an
  output that comes back as an event. Overlapping requests carry an id; a late result is a legal
  event that changes nothing.
- `switch (state, event)` is exhaustive, no `default`, no `_` for the state. Rejected pairs are
  listed and return `(state, [])`.
- Errors are a typed `enum` per feature, mapped once from `TransportError`.

## Dependencies

- A store takes everything in `init`: services as structs of `@Sendable` closures (`.live`,
  `.offline`), other features as protocols from their `*Interface`, `AppGroupStorage`, `now`, a
  clock.
- Never `UserDefaults.standard`, `NotificationCenter`, `SharedFile`, `CatProfile`, `WidgetCenter`
  or a singleton in a feature. Never another feature's concrete store, never `HomeState`.
- A feature imports another only through `<Y>Interface`; `check-imports.mjs` fails the build
  otherwise. A protocol gets the members one consumer needs today.

## Tests

- The transition table, accepted and rejected (`@Test(arguments:)`), in the package's test
  target; the store with a fake interpreter and `await store.settled()`.
- Tests move with the feature into `packages/ios/features/Tests`. No Simulator runs unless a
  specific check is asked for; CI runs the app's tests.

## The Room

- `RoomHost(input: RoomInput, controller:)` with `.equatable()` is the only way in. The input is
  a value (kind, coat, daylight, placed items, polaroids, pins, visibility, interaction). Never a
  store, `HomeState` or a binding.
- Commands go through `RoomControlling` (pet, feed, notice, play, playAll, appOpened); taps and
  cat events come out as `RoomEvent` on one `AsyncStream`. The room writes to no store.
- Ticks, the cat's position, the brain and timers live in the module's internal `RoomModel`.
  The UI reads only `CatStatus`, coarse and throttled, from `RoomController`.
- `visibility`: `.visible` full rate, `.covered` paused, `.hidden` not rendering.
- Outside `apps/ios/Nooki/Room` nothing names `CatRoom`, `DioramaScene`, `CityRoomScene`,
  `BoardRoomScene`, `DioramaView`, `CatDirector`, `CatWalker` or imports RealityKit
  (`check-room-boundary.sh`).
- `RoomProbe` counts body and update evaluations; a change that makes the room re-render from
  outside, or the outside from the room, fails `RoomSealingTests`.
- `CatRoom.swift`, `CityRoomScene.swift`, `DioramaScene.swift`, `DioramaView.swift` are Ilya's.
  A change inside them is listed and asked for through the manager first.
