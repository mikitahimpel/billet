# iOS architecture: feature modules, interfaces, state machines, a sealed Room

How the app in `apps/ios` is put together once the work in #396 and #397 is done, and how it gets
there one feature at a time. Rules first, then the state today, then the migration.

The owner's four asks, 2026-11-06:

1. Make the code more modular.
2. Keep state close to its feature.
3. Features depend on each other only through interfaces (protocols).
4. Describe state as strictly as possible, as state machines with enums, so the app can't reach a
   state we didn't expect.

Plus one that outranks the others: the 3D room with the cat is a sealed module. Nothing outside
makes it re-render unless it really has to, and its ticks never re-evaluate anything outside.

[docs/architecture.md](architecture.md) already sets the pattern (`Machine`, `Store`, typed
throws, injected dependencies) and the packages follow it. This document applies it to the app.
The short version for agents is in `.claude/skills/billet-ios-state/SKILL.md`; the rules that fit
in a line are in AGENTS.md.

## 1. Modules

### 1.1 The graph

```
apps/ios/Nooki                 the App target: composition root (OurioApp), the shell (tabs,
│                              sheets, deep links), nothing else
├── Room/                      the sealed Room module (section 5): RoomHost, the scenes, the cat,
│                              the mini-game stages, the cat's care. The only RealityKit code.
│
packages/ios/features          BilletFeatures, one pair of targets per feature
├── FeatureShop      ShopInterface        Coins and Shop
├── FeatureMoments   MomentsInterface     photos, notes, the board, the journal
├── FeatureUs        UsInterface          lists, wishlist, calendar, dates, Pick tonight, gifts
├── FeatureMood      MoodInterface        check-ins and the mood sync
├── FeatureInbox     InboxInterface       the activity Inbox
├── FeatureGames     GamesInterface       Who knows who, Draw & guess, the mini-games' rules
├── FeatureDraw      DrawInterface        the lock-screen canvas, inks, drawing sync (FeatureCanvas today)
├── FeatureProfile   ProfileInterface     the couple, settings, variants, erase
├── FeatureOnboarding, FeaturePairing     as today, with OnboardingInterface
├── RoomInterface                         RoomInput, RoomEvent, RoomControlling, CatStatus (no scene code)
└── WidgetBridge                          as today
│
packages/ios/{pet, core, design, contracts, payments}     the layers, unchanged
```

Dependencies point one way:

- `Feature<X>` imports: `XInterface`, any other `*Interface`, the layers. Never `Feature<Y>`.
- `<X>Interface` imports: `Wire`, `Pet`, Foundation, Observation, other `*Interface`s. Never a
  `Feature*`, never `Design`, `Transport` or `SwiftUI`.
- The App target imports everything and is the only place a concrete store meets a protocol.
- `Room/` imports `RoomInterface`, `PetScene`, `Pet`, `Design`, `WindowViews`, RealityKit. It
  imports no `Feature*` and no other interface: the room is told what to show, it asks nothing.
- `packages/ios` stays engine-free (`check-imports.mjs`), so the Room implementation cannot be a
  package. Its interface is one; the implementation is an App-target folder with a path check
  (5.8), and later its own static library target like `WindowViews` (5.9).

Enforced by `Package.swift` (SwiftPM already builds with
`--explicit-target-dependency-import-check error`) and by two rules added to
`packages/ios/scripts/check-imports.mjs` (section 7). The widgets and extensions link the
`*Interface` targets they need (value types and file formats) and never a `Feature*`.

### 1.2 What a feature owns

```
Sources/FeatureShop/
  ShopMachine.swift        State, Event, Output, transition      (pure)
  ShopStore.swift          typealias ShopStore = Store<ShopMachine>, the run(output) interpreter
  ShopClient.swift         struct of @Sendable closures over APIClient: .live(api:), .offline
  ShopCatalog.swift        the bundled catalog, offers, prices                        (pure)
  Views/ShopView.swift, Views/ItemSheet.swift, Views/CoinsSheet.swift, …
Sources/ShopInterface/
  Wallet.swift             the one Wallet type; also the App Group file the widget reads
  ShopItem.swift, PaletteInk.swift, Purchase.swift          value types other features show
  CoinsBalanceProviding.swift, CoinEarning.swift, ShopOpening.swift   the protocols
Tests/FeatureShopTests/
  ShopMachineTests.swift   the transition table, accepted and rejected
  ShopStoreTests.swift     the interpreter with a fake client
```

A feature owns its `@Observable` store, its domain types, its views and its tests. Its state is
not readable from outside except through its interface. Nothing in a feature reaches
`UserDefaults.standard`, `NotificationCenter`, `SharedFile`, `CatProfile` or any other global:
what it needs is a parameter of its store's `init` (section 3).

One domain type per concept (#397): the interface target holds the app's type (`Wallet`,
`ShopItem`, `Moment`, `Note`), the feature holds the one tested mapping from the wire type, and
views never see `Wire.*`. The App Group files keep the shape the widgets decode; the type that
encodes them lives in the interface target so both sides compile the same one.

## 2. Interfaces between features

A feature exposes what others need as a small `@MainActor` protocol over `AnyObject`, in its
`*Interface` target. The conformer is the feature's `@Observable` store, so a view that reads a
protocol property re-renders when it changes; Observation tracks through an existential.

| Protocol | In | Members | Used by |
| --- | --- | --- | --- |
| `CoinsBalanceProviding` | ShopInterface | `coins: Int`, `isSynced: Bool` | header, Draw palette, Pet sheet |
| `CoinEarning` | ShopInterface | `earn(EarnEvent)` | Us, Moments (journal), Games |
| `ShopOpening` | ShopInterface | `openShop(at: ShopFocus)` | Draw palette (locked ink), Inbox |
| `TreatBuying` | ShopInterface | `buyTreat() -> Bool` | the Pet sheet in Room |
| `PairProviding` | ProfileInterface | `viewer`, `other`, `partners`, `pairSeed`, `togetherSince` | nearly every feature (24 files today) |
| `RoomChoiceProviding` | ProfileInterface | `variant: RoomsVariant` | shell, Shop (coins sheet), Us (watch list) |
| `WallMomentsProviding` | MomentsInterface | `pinned: [Polaroid]` (ids + file hashes) | the shell, to build `RoomInput` |
| `MomentAdding` | MomentsInterface | `add(image:caption:)`, `addNote(…)` | Us (dates, places), Draw |
| `JournalRecording` | MomentsInterface | `record(JournalEntry)` | Draw, Us, Games |
| `StreakRecording` | UsInterface | `record()` | Mood, Room (pets, treats) |
| `MoodChecking` | MoodInterface | `latest: [String: MoodCheck]`, `set(PartnerMood, note:)` | header, widgets |
| `InboxCounting` | InboxInterface | `unread: Int` | header badge |
| `RoomControlling` | RoomInterface | section 5.3 | the shell, Games, Shop (through the shell) |
| `CatStatusProviding` | RoomInterface | `status: CatStatus` (coarse, throttled) | header badge, Pet sheet |

Rules:

- A protocol has what one consumer needs today, not what a feature could offer. Add members with
  the consumer that needs them.
- Protocols carry value types from an interface target, never a store, never a view, never a
  closure that hands out a store.
- Navigation between features goes through the shell (section 6): a feature asks the shell to
  open something (`ShopOpening` is the shell's conformance, not the Shop's), it never holds another
  feature's view.
- A feature gets its protocols in `init` (stores) or from `@Environment` (views), typed as the
  protocol. Never `HomeState`, never a concrete store of another feature, never a singleton.
- The earn closure `UsStore { shop.earn($0) }` is the shape we already have; it becomes
  `CoinEarning`.

## 3. Dependency injection

- **One composition root.** `OurioApp` builds `AppDependencies.live(session:)` once: every store,
  every client, the `RoomController`. `HomeView` and the shell receive them; nothing below makes
  its own. Widgets and extensions have their own small root over the interface targets' file
  types (`Wallet`, `Us`, `Couple`), never the app's stores.
- **Stores take their dependencies in `init`**, as a `Dependencies` struct of the feature:
  services (structs of `@Sendable` closures with `.live` and `.offline`), the protocols of other
  features, `storage: AppGroupStorage` (Persistence), `now: @Sendable () -> Date`, a `Clock` for
  waits. Nothing optional means "not connected": that is a state (`.offline`).
- **Views** get their own feature's store from `init` or `@Environment(ShopStore.self)`, and other
  features only as protocols through `@Environment(\.coins)`-style keys defined in the interface
  target. A view never builds a store.
- **No globals in features**: no `UserDefaults.standard`, `NotificationCenter.default`,
  `SharedFile`, `CatProfile.store`, `WidgetCenter`. The App Group goes through the injected
  `AppGroupStorage`; preferences through an injected `Preferences` struct of closures; widget
  reloads are an `Output` the app's interpreter runs. `.coupleChanged` and the other
  notifications disappear with the stores they poke.
- **Services are values**, so a test passes a fake inline: `ShopClient(fetch: { snapshot },
  order: { _ in throw .unavailable }, …)`.
- **The server session** (`ServerSession`) stops being a locator every feature reaches into. Each
  feature's client is built from `Backend` in the root and handed to that feature only. The
  session keeps sign-in, pairing state and the socket; the socket's frames arrive in features as
  events (`.pushed(ShopResponse)`), sent by the root.

## 4. State machines

### 4.1 The pattern

`BilletKit` has it already: a `Machine` is a pure `transition(state, event) -> (state, outputs)`
and a `Store<M>` (`@MainActor`, `@Observable`) holds the state, runs outputs through an injected
interpreter and feeds results back as events. Read `packages/ios/core/Sources/BilletKit/Store.swift`
for the contract on overlapping outputs and cancellation.

Every screen and flow state is such a machine:

1. **One `enum State`** with associated values. A case carries only the data valid in it. A
   screen with nothing that changes has no store at all.
2. **One `enum Event`**, one `send`. Views send events; they never assign state. A `Binding` into a
   store's state is forbidden; a sheet's `isPresented` is a `Binding(get: state is .asking,
   set: { if !$0 { store.send(.sheetClosed) } })`.
3. **Outputs describe effects**: a request, a wait, a file write, a widget reload, a call on another
   feature's protocol. The interpreter runs them; the machine never awaits.
4. **Illegal combinations are unrepresentable.** No `isLoading` + `error` + `items`. No optional
   that means a mode (`sync: ShopSync?` becomes `.offline` / `.open`). A list whose items have
   their own lifecycle gives each item a `Stage` enum (`Purchase.stage` below) instead of parallel
   sets.
5. **Overlapping outputs carry a request id**; a late or foreign result is a legal event that
   changes nothing. The transition for it is written down, not left to a wildcard.
6. **Typed errors per feature**: `enum ShopError: Error`, mapped once from `TransportError` in an
   `init`, exhaustive over its cases as `PairingFailure` does.
7. **`switch (state, event)` is exhaustive, no `default`**, no `_` in the state position. Rejected
   pairs are listed, grouped, and return `(state, [])`. Adding a case fails the build until each
   pairing is decided.
8. **The store exposes `state` read-only** plus derived values for the views (`coins`, `owned`).
   Derived values are computed from `state`, never cached beside it.
9. **Time is an event**: a timeout or a window is an output that waits and comes back as an event
   (`.undoWindowPassed`), so a test drives it without sleeping.

### 4.2 Worked example: Coins and Shop

What `ShopModel` + `WalletStore` + `CatCare.fed/notice` + `CoinsAsk` + `Purchase` do today
(`apps/ios/Nooki/Model/ShopModel.swift`), as a machine. Behaviour is the same: only the server
changes coins; a buy shows at once, waits out its Undo window, then is ordered under one
idempotency key with retries; a refused buy is taken back and the room read again; the Coins
sheet opens for a buy the balance doesn't cover and finishes it once it does.

```swift
// ShopInterface
public struct Wallet: Codable, Hashable, Sendable {        // the App Group file, as today
  public var coins = 0, level = 1, progress = 0.0
  public var owned: Set<String> = ["lamp", "rug"], wishlist: Set<String> = [], gifted: Set<String> = []
}

public enum ShopError: Error, Equatable, Sendable {
  case notEnoughCoins(needed: Int, have: Int)
  case giftTaken(day: String)
  case bonusTaken
  case alreadyOwned
  /// The network or the server, after the retries. Trying again is safe.
  case unavailable
  case signedOut

  public init(_ error: TransportError) { /* exhaustive over TransportError, as PairingFailure */ }
}
```

```swift
// FeatureShop/ShopMachine.swift
public enum ShopMachine: Machine {

  /// One buy from the tap until the server answers.
  public struct Purchase: Identifiable, Equatable, Sendable {
    public let id: UUID                       // the order's idempotency key on every retry
    public let offer: ShopOffer, itemIDs: [String], added: [String], cost: Int, placedAt: Date
    public let title: String, kind: Kind, asGift: Bool
    public var stage: Stage

    public enum Kind: Equatable, Sendable { case item, ink, treat }
    public enum Stage: Equatable, Sendable {
      /// Shown, Undo offered, not yet ordered.
      case undoable
      /// The window passed (or a treat, which has none): on its way, `attempt` tries so far.
      case ordering(attempt: Int)
    }
  }

  /// What the purchase moment shows.
  public enum Moment: Equatable, Sendable {
    case placed(Purchase.ID)
    case refused(Purchase)
  }

  /// The pair's shop as the server keeps it, plus the buys it hasn't heard of yet.
  public struct PairShop: Equatable, Sendable {
    public var wallet: Wallet
    public var giftDay: String?
    public var bonuses: Set<String> = []
    public var inks: [PaletteInk]
    public var history: [CoinEntry] = []
    public var pending: [Purchase] = []
    public var moment: Moment?
    public var fetch: Fetch = .idle

    public enum Fetch: Equatable, Sendable { case idle, reading(request: Int) }

    public var coins: Int { max(0, wallet.coins - pending.reduce(0) { $0 + $1.cost }) }
    public var owned: Set<String> { wallet.owned.union(pending.flatMap(\.added)) }
  }

  public enum State: Equatable, Sendable {
    /// No pair's room on the server: nothing can be bought or earned. A buy is refused out loud.
    case offline(refused: Purchase?, ask: CoinsAsk?)
    case open(PairShop)

    public static let initial = State.offline(refused: nil, ask: nil)
  }

  public enum Event: Equatable, Sendable {
    // From the shell
    case paired(PairSeed)
    case unpaired
    case foregrounded
    case pushed(ShopSnapshot)                       // the socket's shop frame
    case earnAsked(EarnEvent)                       // CoinEarning
    // From the views
    case buyTapped(Order)                           // item, set, ink: offer + itemIDs + cost + title + kind + asGift
    case treatTapped
    case undoTapped(Purchase.ID)
    case wishToggled(itemID: String)
    case giftTapped
    case bonusTapped(collectionID: String)
    case coinsTapped
    case coinsSheetClosed
    case retryTapped                                // the buy the sheet was opened for
    // Results
    case fetched(ShopSnapshot, request: Int)
    case fetchFailed(request: Int)
    case inksLoaded([PaletteInk])
    case undoWindowPassed(Purchase.ID)
    case ordered(Purchase.ID, ShopSnapshot)
    case orderFailed(Purchase.ID, ShopError)
    case wished(ShopSnapshot)
    case giftOpened(GiftReward, ShopSnapshot)
    case giftFailed(ShopError)
    case bonusClaimed(ShopSnapshot)
    case bonusFailed(ShopError)
    case balance(Int)                               // an earn's answer
  }

  public enum Output: Equatable, Sendable {
    case follow(PairSeed)                           // the interpreter builds the client
    case forget
    case fetch(request: Int)
    case loadInks
    case wait(Purchase.ID, until: Date)             // comes back as .undoWindowPassed
    case order(Purchase)                            // retries inside; one result
    case wish(itemID: String, wished: Bool)
    case openGift
    case claimBonus(collectionID: String)
    case earn(EarnEvent)
    case saveWallet(Wallet)
    case reloadWidgets
    case catFed                                     // RoomControlling.feed()
    case catNoticed                                 // RoomControlling.notice()
    case giftOutcome(GiftOutcome)                   // the gift card's animation
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {

    // Following a pair and leaving it: legal from every state.
    case (.offline(let wallet), .paired(let seed)):
      return (.loading(wallet, request: 1), [.follow(seed), .fetch(request: 1), .loadInks])
    case (.loading(let wallet, let request), .paired(let seed)):
      return (.loading(wallet, request: request + 1), [.follow(seed), .fetch(request: request + 1)])
    case (.open(let shop), .paired(let seed)), (.askingCoins(let shop, _), .paired(let seed)):
      // A new pair: start over from its room, the old pending buys dropped with the old client.
      return (.loading(shop.wallet, request: 1), [.follow(seed), .fetch(request: 1), .loadInks])
    case (.loading(let wallet, _), .unpaired), (.offline(let wallet), .unpaired):
      return (.offline(wallet), [.forget])
    case (.open(let shop), .unpaired), (.askingCoins(let shop, _), .unpaired):
      return (.offline(shop.wallet), [.forget, .saveWallet(shop.wallet), .reloadWidgets])

    // First read.
    case (.loading(_, let request), .fetched(let snapshot, let answered)) where answered == request:
      let shop = PairShop(snapshot: snapshot, inks: PaletteInk.bundled)
      return (.open(shop), [.saveWallet(shop.wallet), .reloadWidgets])
    case (.loading(let wallet, let request), .fetchFailed(let answered)) where answered == request:
      return (.loading(wallet, request: request + 1), [.fetch(request: request + 1)])  // the client's retries are inside .order/.fetch; this is the foreground re-read

    // Buying.
    case (.open(var shop), .buyTapped(let order)):
      let added = order.itemIDs.filter { !shop.owned.contains($0) }
      guard !added.isEmpty else { return (state, []) }                       // owned already
      guard shop.coins >= order.cost else {
        return (.askingCoins(shop, CoinsAsk(missing: order.cost - shop.coins, retry: order)), [])
      }
      let purchase = Purchase(order, added: added, stage: .undoable)
      shop.pending.append(purchase)
      shop.moment = .placed(purchase.id)
      return (.open(shop), [.wait(purchase.id, until: purchase.placedAt + undoWindow), .catNoticed])

    case (.open(var shop), .treatTapped):
      guard shop.coins >= treatPrice else {
        return (.askingCoins(shop, CoinsAsk(missing: treatPrice - shop.coins, retry: .treat)), [])
      }
      let treat = Purchase(.treat, stage: .ordering(attempt: 1))
      shop.pending.append(treat)
      return (.open(shop), [.order(treat), .catFed])

    case (.open(var shop), .undoTapped(let id)):
      guard let i = shop.pending.firstIndex(where: { $0.id == id }), shop.pending[i].stage == .undoable
      else { return (state, []) }                                             // too late, or unknown
      shop.pending.remove(at: i)
      if shop.moment == .placed(id) { shop.moment = nil }
      return (.open(shop), [])

    case (.open(var shop), .undoWindowPassed(let id)):
      guard let i = shop.pending.firstIndex(where: { $0.id == id }) else { return (state, []) }  // undone
      shop.pending[i].stage = .ordering(attempt: 1)
      return (.open(shop), [.order(shop.pending[i])])

    case (.open(var shop), .ordered(let id, let snapshot)):
      guard let purchase = shop.pending.first(where: { $0.id == id }) else { return (state, []) }
      shop.pending.removeAll { $0.id == id }
      shop.apply(snapshot)
      if purchase.asGift { shop.wallet.gifted.formUnion(purchase.added) }
      return (.open(shop), [.saveWallet(shop.wallet), .reloadWidgets])

    case (.open(var shop), .orderFailed(let id, let error)):
      guard let purchase = shop.pending.first(where: { $0.id == id }) else { return (state, []) }
      shop.pending.removeAll { $0.id == id }
      if shop.moment == .placed(id) { shop.moment = nil }
      let next = shop.fetch.next
      shop.fetch = .reading(request: next)
      switch error {
      case .notEnoughCoins(let needed, let have):
        // The partner spent the coins first: offer to top up and finish, rather than only refusing.
        return (.askingCoins(shop, CoinsAsk(missing: needed - have, retry: Order(purchase))), [.fetch(request: next)])
      case .alreadyOwned, .unavailable, .signedOut, .giftTaken, .bonusTaken:
        if purchase.kind != .treat { shop.moment = .refused(purchase) }
        return (.open(shop), [.fetch(request: next)])
      }

    // The Coins sheet.
    case (.open(let shop), .coinsTapped):
      return (.askingCoins(shop, CoinsAsk(missing: 0, retry: nil)), [])
    case (.askingCoins(let shop, _), .coinsSheetClosed):
      return (.open(shop), [])
    case (.askingCoins(let shop, let ask), .retryTapped):
      guard let retry = ask.retry else { return (state, []) }
      return transition(.open(shop), retry == .treat ? .treatTapped : .buyTapped(retry))
    case (.askingCoins(var shop, let ask), .pushed(let snapshot)), (.askingCoins(var shop, let ask), .fetched(let snapshot, _)):
      shop.apply(snapshot)                                                    // the balance the sheet shows
      return (.askingCoins(shop, ask), [.saveWallet(shop.wallet), .reloadWidgets])

    // The server's view of the shop, however it arrives.
    case (.open(var shop), .pushed(let snapshot)):
      shop.apply(snapshot)
      return (.open(shop), [.saveWallet(shop.wallet), .reloadWidgets])
    case (.open(var shop), .fetched(let snapshot, let answered)):
      guard shop.fetch == .reading(request: answered) else { return (state, []) }
      shop.fetch = .idle
      shop.apply(snapshot)
      return (.open(shop), [.saveWallet(shop.wallet), .reloadWidgets])
    case (.open(var shop), .foregrounded):
      let next = shop.fetch.next
      shop.fetch = .reading(request: next)
      return (.open(shop), [.fetch(request: next)])
    case (.open, .earnAsked(let event)):
      return (state, [.earn(event)])
    case (.open(var shop), .balance(let coins)):
      shop.wallet.coins = coins
      return (.open(shop), [.saveWallet(shop.wallet), .reloadWidgets])

    // Gift, bonus, wish, inks: the same shape (an output, one result event, a snapshot applied).
    case (.open, .giftTapped), (.open, .giftOpened), (.open, .giftFailed), (.open, .bonusTapped),
      (.open, .bonusClaimed), (.open, .bonusFailed), (.open, .wishToggled), (.open, .wished),
      (.open, .inksLoaded):
      return gifts(state, event)

    // Rejected: nothing to buy, earn or undo without a room; results for a shop we left; taps
    // while the Coins sheet covers the shop; a first read's results after the state moved on.
    case (.offline, .buyTapped), (.offline, .treatTapped), (.offline, .undoTapped), (.offline, .wishToggled),
      (.offline, .giftTapped), (.offline, .bonusTapped), (.offline, .coinsTapped), (.offline, .retryTapped),
      (.offline, .coinsSheetClosed), (.offline, .earnAsked), (.offline, .foregrounded), (.offline, .pushed),
      (.offline, .fetched), (.offline, .fetchFailed), (.offline, .inksLoaded), (.offline, .undoWindowPassed),
      (.offline, .ordered), (.offline, .orderFailed), (.offline, .wished), (.offline, .giftOpened),
      (.offline, .giftFailed), (.offline, .bonusClaimed), (.offline, .bonusFailed), (.offline, .balance),
      (.loading, .buyTapped), (.loading, .treatTapped), /* … every view event and result but .fetched/.fetchFailed/.inksLoaded with the right request */
      (.askingCoins, .buyTapped), (.askingCoins, .treatTapped), (.askingCoins, .coinsTapped), /* … */
      (.open, .coinsSheetClosed), (.open, .retryTapped),
      (.loading, .fetched), (.loading, .fetchFailed):                        // a stale request
      return (state, [])
    }
  }
}
```

The real file (`packages/ios/features/Sources/FeatureShop/ShopMachine.swift`) is the one to read:
it switches over the state first and then over every event, so each pairing is written down, and
it keeps the Coins sheet as `ask` inside both states rather than as a state of its own, because the
sheet can open over an offline shop too and the buy it retries runs the ordinary `.buyTapped`.
A buy's `id` and `date` arrive in the event, so the transition stays pure and a test can name them.
The sketch above shows the shape; the ellipses are only in this document. Helpers
(`PairShop.apply(_:)`, `Fetch.next`, `gifts(_:_:)`) are private, pure functions beside the
transition. Prices and offers are pure too (`ShopOffers`, `ShopCatalog`), kept out of the machine.

```swift
// FeatureShop/ShopStore.swift
public typealias ShopStore = Store<ShopMachine>

extension ShopStore {
  public struct Dependencies: Sendable {
    public var api: APIClient
    public var storage: AppGroupStorage             // the wallet file
    public var room: any RoomControlling            // feed, notice
    public var widgets: @Sendable () -> Void        // WidgetCenter reload, run by the app
    public var now: @Sendable () -> Date
    public var clock: any Clock<Duration>
    public var retries: Int = 3
  }

  public static func shop(_ deps: Dependencies, wallet: Wallet) -> ShopStore {
    let client = ShopClients()                      // an actor holding the client for the pair followed
    return ShopStore(initial: .initial(wallet: wallet)) { output in
      switch output {
      case .follow(let seed): await client.follow(ShopClient.live(api: deps.api, seed: seed)); return nil
      case .forget: await client.forget(); return nil
      case .fetch(let request):
        do { return .fetched(try await client.fetch(), request: request) }
        catch { return .fetchFailed(request: request) }
      case .wait(let id, let until):
        try? await deps.clock.sleep(for: .seconds(until.timeIntervalSince(deps.now())))
        return .undoWindowPassed(id)
      case .order(let purchase):
        do { return .ordered(purchase.id, try await client.order(purchase, retries: deps.retries)) }
        catch { return .orderFailed(purchase.id, ShopError(error)) }
      case .saveWallet(let wallet): try? deps.storage.writeJSON(wallet, to: Wallet.file); return nil
      case .reloadWidgets: deps.widgets(); return nil
      case .catFed: await deps.room.feed(); return nil
      case .catNoticed: await deps.room.notice(); return nil
      // … wish, openGift, claimBonus, earn, loadInks, giftOutcome
      }
    }
  }
}

extension ShopStore: CoinsBalanceProviding, CoinEarning, TreatBuying {
  public var coins: Int {
    switch state {
    case .offline(let wallet), .loading(let wallet, _): wallet.coins
    case .open(let shop), .askingCoins(let shop, _): shop.coins
    }
  }
  public func earn(_ event: EarnEvent) { send(.earnAsked(event)) }
  public func buyTreat() -> Bool { send(.treatTapped); if case .open = state { return true } else { return false } }
}
```

A view:

```swift
struct BuyButton: View {
  @Environment(ShopStore.self) private var shop
  let order: Order
  var body: some View {
    PriceButton(price: order.cost, owned: shop.owned.isSuperset(of: order.itemIDs)) { shop.send(.buyTapped(order)) }
  }
}

// In ShopView: the Coins sheet is the state, not a flag.
.sheet(isPresented: Binding(get: { if case .askingCoins = shop.state { true } else { false } },
                            set: { if !$0 { shop.send(.coinsSheetClosed) } })) { CoinsSheet() }
```

Tests (Swift Testing, in the package):

```swift
@Test func buyWaitsOutUndoThenOrders() {
  let (s1, o1) = ShopMachine.transition(.open(shop(coins: 200)), .buyTapped(lamp))
  #expect(o1 == [.wait(id(s1), until: placedAt + 5), .catNoticed])
  let (s2, o2) = ShopMachine.transition(s1, .undoWindowPassed(id(s1)))
  #expect(o2 == [.order(pending(s2)[0])])
  #expect(pending(s2)[0].stage == .ordering(attempt: 1))
}

@Test func undoAfterTheWindowChangesNothing() { … stage .ordering → (state, []) }

@Test(arguments: [
  (ShopMachine.State.offline(.init()), ShopMachine.Event.buyTapped(lamp)),
  (.offline(.init()), .treatTapped),
  (.askingCoins(open, ask), .buyTapped(lamp)),
  (.loading(.init(), request: 2), .fetched(snapshot, request: 1)),
  (.open(open), .ordered(UUID(), snapshot)),
])
func rejected(state: ShopMachine.State, event: ShopMachine.Event) {
  let (next, outputs) = ShopMachine.transition(state, event)
  #expect(next == state)
  #expect(outputs.isEmpty)
}

@Test func storeOrdersThroughTheClient() async {
  var ordered: [UUID] = []
  let store = ShopStore(initial: .open(shop(coins: 200))) { output in
    if case .order(let p) = output { ordered.append(p.id); return .ordered(p.id, snapshot) }
    return nil
  }
  store.send(.buyTapped(lamp)); store.send(.undoWindowPassed(id(store.state)))
  await store.settled()
  #expect(ordered.count == 1)
}
```

`ShopModelTests` (18 tests) port one to one; each becomes a transition test or a store test with
a fake. `ShopBuyTests` (UI) stays as it is and must stay green.

## 5. The Room is a sealed module

The 3D room with the cat is fully encapsulated. This is the second migration (section 8), right
after Coins and Shop, and billet-perf measures its effect.

### 5.1 One entry point

```swift
// RoomInterface
public struct RoomInput: Equatable, Sendable {
  public var kind: RoomKind                      // .home, .city, .board
  public var coat: CatCoat
  public var daylight: DaylightPhase             // coarse: morning, day, evening, night
  public var placed: Set<RoomItemID>             // owned pieces in the room
  public var polaroids: [Polaroid]               // pinned moment ids and file hashes, for the wall
  public var pins: [BoardPin]                    // the board's cards
  public var visibility: RoomVisibility
  public var interaction: RoomInteraction        // .free, .locked (a game, a focused photo)
}

public enum RoomVisibility: Equatable, Sendable {
  case visible
  /// A sheet or the canvas over it: a low frame rate or paused.
  case covered
  /// Another tab or the background: not rendering.
  case hidden
}
```

```swift
// Room/RoomHost.swift (the App target, folder Nooki/Room)
public struct RoomHost: View, Equatable {
  public let input: RoomInput
  public let controller: RoomController          // identity only; not observed by the host
  public static func == (a: Self, b: Self) -> Bool { a.input == b.input && a.controller === b.controller }
  public var body: some View { RoomProbe.bodies.add(1); … }
}

// The shell:
RoomHost(input: roomInput, controller: room).equatable()
```

`roomInput` is a value the shell derives from coarse state (tab, open sheets, scene phase, the
coat, the pinned polaroids' ids, the owned set). The host re-evaluates only when the value
changes. The parent cannot pass `HomeState`, a store or a binding: the initializer has none.

### 5.2 Events out, not state out

```swift
public enum RoomEvent: Equatable, Sendable {
  case ready                                     // first frame drawn; the splash can lift
  case catPetted
  case itemTapped(RoomItemID)
  case photoTapped(MomentID), photoLeft
  case pinOpened(UUID), drawAsked                // the board
  case showcase(String?)                         // Play all's label
  case gameFinished(GameResult)
  case roomOpened(RoomKind)                      // analytics
}

@MainActor public protocol RoomControlling: AnyObject {
  var events: AsyncStream<RoomEvent> { get }
  func pet()                                     // a widget pet arriving
  func feed()                                    // a treat was bought
  func notice()                                  // something new in the room
  func appOpened()
  func play(_ game: MiniGame)
  func endGame()
  func playAll()
}
```

The room never writes to another store. What a tap means (open the pet sheet, record a pet in the
journal, send `.petted` to the server once per 10 min) is the shell's and the features' business,
driven from `events`.

### 5.3 Ticks stay inside

- The cat's position, the animation clocks, the brain (`CatDirector`), the bubble spot, the
  timers and the game stages live in `RoomModel`, an `@Observable` that is `internal` to the
  module. Nothing outside can observe it.
- The RealityKit update loop (`CatRoom.start(updatesFrom:)`) touches only `RoomModel` and the
  entities. It never reaches SwiftUI state outside the module: no closure it calls assigns to a
  store or a `@State` of the shell.
- What the UI needs from the room (the mood for the header badge, needs for the Pet sheet, the
  level) comes as `CatStatus`, a coarse value on `RoomController`:

```swift
public struct CatStatus: Equatable, Sendable {
  public var mind: CatMind                       // awake, resting, social
  public var needs: Needs                        // each rounded to 1/20
  public var level: Int
}
@MainActor public protocol CatStatusProviding: AnyObject { var status: CatStatus { get } }
```

  It is set only when the rounded value differs from the last one, and at most once a second.
  The director's raw values stay inside.

### 5.4 Visibility

| `visibility` | RealityView | `CatRoom.paused` | ticks |
| --- | --- | --- | --- |
| `.visible` | mounted | false | full rate |
| `.covered` | mounted, under the cover | true | the brain's 1 Hz tick only |
| `.hidden` | not mounted (as `roomOnScreen` does today) | n/a | the brain's 1 Hz tick only |

The last-frame stand-in (`worldSnapshot`) and the splash stay in the shell for now; they are
pixels, not state. `.hidden` keeps `CatRoom` loaded, as today, so coming back makes a new view
only.

### 5.5 What moves into `Nooki/Room`

The Scene folder as it is (the original author's files untouched, see 5.7), plus the code that reaches into it
today: `Games/*` (stages, `GameSession`, `GameCamera`, `GameView`), `Model/CatCare.swift`,
`UI/Home/PetSheet`, `NeedBars`, `BrainCard`, `HeartBubble`, `PetButton`, `Perf/OurioPerf.swift`
(the scene part), the room's part of `HomeView` (building the scenes, the room switch's scene
side, `setPolaroids`, `setPins`, `purr`, `appOpened`, `stop`), and `ItemSheet`'s use of
`CatRoom.gradientImage` (becomes a `Design` helper).

Leaks today, from the census: `CatRoom` is named in 11 files outside Scene, `BoardRoomScene` in
4, `CatDirector` in 2 (NeedBars, BrainCard read 15 of its members), `DioramaView` in 2.

### 5.6 Proof, not hope

- `RoomProbe` (in the module): atomic counters `bodies` (RoomHost body evaluations) and
  `updates` (RealityView update closures), plus `ShellProbe` counters the shell registers for the
  header, the tab bar and an open sheet. An atomic increment is free, so they stay in Release and
  the perf runs read them; the reset and read hooks are `public` for tests.
- `OurioTests/RoomSealingTests`: hosts the shell with fakes and the stand-in room (`-uitestNoRoom`,
  CI's virtual Macs can't draw RealityKit). Changing coins, setting a mood, opening the Coins
  sheet and scrolling the Shop list leave `RoomProbe.bodies` unchanged. Then 10 s of stand-in
  ticks (the internal model mutated at 60 Hz) leave the header's, the tab bar's and the sheet's
  counters unchanged. They are unit tests under `UIHostingController`, not UI tests, so they run
  in the ordinary `ios.yml` check.
- `perf.yml`: the census line (`ScenePerf.Host.census`) gains `room_bodies`, `room_updates`,
  `header_bodies`, `tabbar_bodies` for the steady and full runs; `report.py` already turns every
  census key into an A/B metric. A regression shows as a count, next to the frame times.

### 5.7 The original author's files

The boundary sits around `DioramaView` and what it uses: `CatRoom.swift`, `CityRoomScene.swift`,
`DioramaScene.swift`, `DioramaView.swift` are not changed by the sealing. `RoomHost` wraps
`DioramaView` as it is; the closures `CatRoom` already offers (`onShowcase`, `onFocusChange`,
`onOpen`, `onDraw`, `onPet`) are wired to the event stream from the module's side. The room's
`paused` flag and its unmounting when hidden are what `HomeView` does today.

If the sealing turns out to need a change inside one of the four files, the PR lists the exact
change and asks the manager first; the owner and the original author decide. Candidates known now: none. A
possible one later: `BubbleSpot` in `DioramaView` is already private to the view, so it stays.

### 5.8 Enforcement

`apps/ios/scripts/check-room-boundary.sh`, run by `ios.yml` before the build: outside
`apps/ios/Nooki/Room/`, no Swift file in the app target may mention `CatRoom`, `DioramaScene`,
`CityRoomScene`, `BoardRoomScene`, `DioramaView`, `CatDirector`, `CatWalker`, `RoomModel` or
`import RealityKit`. A grep, not hope.

### 5.9 Later: a library target

Once sealed, `Nooki/Room` can become a static library target `OurioRoom` in `project.yml`, like
`WindowViews`: then `internal` means internal and the grep is redundant. That moves the original author's files
(a rename, no content change) and needs the owner's OK; it is not part of the sealing PR.

## 6. The shell, and the end of HomeState

`HomeState` shrinks with every migration and goes away in the last one. What remains is the
shell: which tab, which route, which sheet, as one machine:

```swift
enum ShellMachine: Machine {
  enum State: Equatable, Sendable {
    case onboarding(OnboardingRoute)
    case home(tab: HomeTab, room: RoomKind, route: Route?, momentsMode: MomentsMode)

    enum Route: Equatable, Sendable {
      case profile, inbox, petSheet, pairing(code: String), game(MiniGame)
      case shopItem(RoomItemID), coins(CoinsAsk), composing(NoteComposer.Mode), drawing
      case pin(UUID), us(UsRoute)
    }
  }
  enum Event { case tabTapped(HomeTab), link(DeepLink), activity(ActivityTarget), roomEvent(RoomEvent), routeClosed, … }
}
```

One route at a time is what the screen can show; the enum says so. Deep links and Inbox targets
(`HomeState.open(_:)` and `HomeState+Activity`) become `.link` and `.activity` events whose
transitions are tested. `ShopOpening` is the shell's conformance: `openShop(at:)` sends
`.link(.shop(focus))`.

The composition root (`OurioApp`) builds `AppDependencies.live(session:)` and the shell store;
`HomeView` becomes the shell's view: the tab views, the sheets by route, `RoomHost` with the
input derived from the shell state and the interfaces. `followPair`, `refresh`, `eraseAll`,
`didEnterBackground` become events the root sends to the features that own them.

## 7. Enforcement in CI

`packages/ios/scripts/check-imports.mjs`, run by every package's `ios:build` and `ios:test`,
gains two rules beside the engine rule:

- A file under `Sources/Feature<X>/` may not `import Feature<Y>` for any other `Y`.
- A file under `Sources/<X>Interface/` may not import any `Feature*`, `Design`, `Transport` or
  `SwiftUI`.

`Package.swift` lists the same dependencies, and SwiftPM's explicit-dependency check already
fails an import that is not declared; the script makes the rule visible in the diff and catches a
`Package.swift` edit that would allow it.

`apps/ios/scripts/check-room-boundary.sh` (5.8) runs in `ios.yml`.

## 8. Migration

### 8.1 Today

`HomeState` (`apps/ios/Nooki/Model/HomeState.swift`, 278 lines) holds the shell's navigation and
the 13 stores of `HomeStores`. 48 views take the whole object; 58 files name it.

| Slice | HomeState members | Read by | Written by |
| --- | --- | --- | --- |
| Shell | `tab`, `room`, `game`, `showsProfile`, `showsInbox`, `invitedCode`, `showsPetSheet`, `openedShopItem`, `usRoute`, `composingNote`, `drawing`, `openedPin`, `momentsMode`, `open(DeepLink)`, `open(ActivityTarget)` | HomeView, TabBar, AppHeader, MomentsView, Us screens, OurioPerf | the same views: `tab` from 7 files, `composingNote` from 4, `usRoute` from 4 |
| Coins and Shop | `shop`, `wallet`, `shopFocus`, `openShop` | 19 files: Shop views, Draw (InkPalette, InkShelf, LockCanvasView), AppHeader, PetSheet, ItemSheet | ShopModel itself; `wallet` by CatCare |
| Room and cat | `care`, `game`, `showsPetSheet` | HomeView, PetSheet | HomeView (petPulse into DioramaView) |
| Moments | `moments`, `notes`, `journal`, `openedPin`, `momentsMode`, `composingNote` | 10 + 6 + 5 files: Moments views, BoardFaces, Us (dates, places add photos), Draw, TabBar | Moments views, Draw, Us, HomeView+Pair (board) |
| Us | `us`, `gifts`, `lists`, `streak`, `usRoute` | 16 Us files, TabBar | Us screens |
| Mood | `partnerMoods`, `moodSync`, `setMood` | HeaderControls, MoodPicker | HomeView+Pair |
| Profile | `profile`, `rooms`, `viewer`, `partners`, `eraseAll` | 24 files for `profile` (every feature), 6 for `rooms` | HomeView+Pair (adopt, leavePair), ProfileHub |
| Inbox | `showsInbox`, `open(ActivityTarget)` | HomeView, AppHeader | HomeView+Activity |

Besides HomeState: `HomeView` (450 lines + 100 in `HomeView+Pair`) builds the three scenes, wires
sync for shop, gifts, lists, moods, photos and notes, owns the splash, the snapshots and the room
switch, and reacts to 10 `onChange`s. Stores construct themselves 16 times outside
`HomeStores.live()` (the widgets, the share extension, the intents, tests). Two
`NotificationCenter` names (`coupleChanged`, `pushTokenChanged`) stand in for state.
`ServerSession` is a locator: 12 features reach into it for their client.

### 8.2 Order and shape

One feature per PR, branch `arch/<feature>` from `origin/main`, merged the same day. Each PR
moves one feature fully: store, enum machine, interface, tests, views, and its slice out of
`HomeState`. Behaviour and look do not change. The next PR opens as soon as the previous one is
open.

| # | PR | Moves | Interface | Leaves HomeState | Stays shippable because |
| --- | --- | --- | --- | --- | --- |
| 0 | `arch/plan` | this doc, AGENTS.md, the skill, the two script rules (no code moves) | | | docs only |
| 1 | `arch/shop` | ShopModel → ShopMachine + ShopStore; Shop, ShopOffers, ShopPurchase, CoinPacksModel, ShopSync → ShopClient, ShopFixture, PaletteInk, Inks catalog; ShopView, UI/Shop/*, ItemSheet, CoinsSheet; `Wallet` → ShopInterface; WalletStore deleted | CoinsBalanceProviding, CoinEarning, ShopOpening, TreatBuying | `shop`, `wallet`, `shopFocus`, `openedShopItem`, `openShop`, the `-shopCoins` args | the 19 readers switch from `state.shop` to `@Environment(ShopStore.self)` or a protocol; CatCare stays in the app and is passed as closures; ShopModelTests port; ShopBuyTests unchanged |
| 2 | `arch/room` | section 5.5 into `Nooki/Room`; RoomInterface; RoomHost, RoomController, RoomModel, RoomProbe; the probe tests; the perf census keys; the boundary script | RoomControlling, CatStatusProviding | `care`, `game`, `showsPetSheet`, `room` (to the shell's state) | HomeView keeps its layout, swaps the DioramaView block for RoomHost; the original author's four files untouched; the games' UI tests unchanged |
| 3 | `arch/moments` | MomentStore, NoteStore, Journal, PhotoSync, TextNoteSync, BoardFaces, Moments views, NoteComposer, NoteSheet, NotesHistory, ComposeSheet; joins FeatureMoments (reactions) | WallMomentsProviding, MomentAdding, JournalRecording | `moments`, `notes`, `journal`, `openedPin`, `momentsMode`, `composingNote` | `RoomInput.polaroids` and `pins` come from the interface; Us and Draw add through MomentAdding |
| 4 | `arch/us-lists` | UsStore (lists, wishlist, grocery), GiftsModel, ListsModel, ListSync, GiftSync, ListActivity, GroceryCatalog, UI/Us list screens, share extension's write | UsInterface: ListsProviding (widgets, intents) | `us` (part), `gifts`, `lists` | UsStore stays whole behind the store until PR 5; the widgets read the Us file through the interface |
| 5 | `arch/us-dates` | calendar, dates, Pick tonight, DateReminders, PickTonightSync, TitleSource, StreakStore, the rest of UI/Us | StreakRecording | `us`, `streak`, `usRoute` | `UsRoute` becomes a shell route |
| 6 | `arch/mood` | MoodStore, MoodSync, MoodPicker, HeaderControls' mood part, `setMood` | MoodChecking | `partnerMoods`, `moodSync`, `setMood` | the widget's intent writes through the interface's file type |
| 7 | `arch/inbox` | InboxModel, InboxView, InboxLine, InboxLink, HomeState+Activity | InboxCounting | `showsInbox`, `open(ActivityTarget)` → shell event | targets become `ShellMachine.Event.activity`, tested as InboxTests are today |
| 8 | `arch/games` | WhoKnowsModel, DrawGuessModel, their syncs and screens; joins FeatureGames | GamesInterface (results for the journal) | nothing left; `usRoute` cases | the mini-game stages stayed in Room in PR 2 |
| 9 | `arch/draw` | DrawModel, LockCanvasView, InkPalette, InkShelf, DrawingSync; joins FeatureCanvas as FeatureDraw | DrawInterface | `drawing` | the Live Activity and widgets keep their files |
| 10 | `arch/profile` | CoupleStore, RoomsChoice, ProfileHub, ProfileEditor, SettingsView, StyleGallery, `eraseAll` | PairProviding, RoomChoiceProviding | `profile`, `rooms`, `viewer`, `partners`, `eraseAll`, `showsProfile` | `.coupleChanged` goes; 24 readers take the protocol |
| 11 | `arch/onboarding` | OnboardingFlow, OnboardingView, CoatPicker, AnswerQueue, OnboardingClient, PairingSheet into the packages | OnboardingInterface | `invitedCode` | FeatureOnboarding and FeaturePairing exist; this is the app side |
| 12 | `arch/shell` | ShellMachine, AppDependencies, the root; HomeState and HomeStores deleted; ServerSession split into per-feature clients | | everything | HomeView is the shell's view; the end state of section 6 |

PR 7 went in two parts. `InboxMachine`, `InboxModel` and `InboxDay` are in `FeatureInbox` with their
tests. `InboxView` and `InboxLine` stay in the app until `PartnerMood`, `ListKind` and `MoodArt` leave
`apps/ios/Shared`.

PRs 3 to 11 can be reordered around other agents' work; 1 and 2 cannot. Where a PR would touch
more than about 25 files of UI that others are editing, it splits: the store and interface first
(the views keep reading the old property through a one-line forward for a day), the views next.

### 8.3 Each PR, the same checklist

- The machine's transition table is tested, accepted and rejected pairs.
- The feature's tests moved into the package test target; app-target tests only for composition.
- `pnpm turbo run ios:test` (packages) and the app's tests on CI are green; no local Simulator
  runs unless a specific check is asked for.
- The HomeState slice is deleted, not forwarded (except the one-day forward above).
- No new `UserDefaults.standard`, `NotificationCenter`, `SharedFile` or `CatProfile` in the
  feature.
- `check-imports.mjs` and `check-room-boundary.sh` pass.
- Look and behaviour unchanged: the UI tests that cover the feature stay as they are.
