import Design
import FeatureInbox
import FeatureShop
import Foundation
import GamesInterface
import Payments
import ShopInterface
import SwiftUI
import Testing
import WidgetBridge
@testable import Billet

/// Every design component, and the key screens, at the SE and Pro Max sizes and at the largest accessibility text
/// size, against the references in packages/ios/design/Tests/Gallery. Run with `scripts/gallery.sh`.
@MainActor @Suite(.serialized) struct GalleryTests {
    @Test(arguments: GalleryPage.allCases, Snapshot.Variant.allCases)
    func component(_ page: GalleryPage, _ variant: Snapshot.Variant) throws {
        let name = "\(page.rawValue)-\(variant.rawValue)"
        let view = page.view.padding(.vertical, Space.l).frame(maxWidth: .infinity).background(Ink.screen)
        let image = try #require(Snapshot.render(view, variant: variant, fits: true), "\(name) drew nothing")
        try Snapshot.match(image, name: name)
    }

    @Test(arguments: GalleryScreen.allCases, Snapshot.Variant.allCases)
    func screen(_ screen: GalleryScreen, _ variant: Snapshot.Variant) async throws {
        let name = "screen-\(screen.rawValue)-\(variant.rawValue)"
        // A task of the view never runs while the drawing waits on the run loop, so a screen that loads is given the
        // answer it would have by the time it is drawn.
        let model = await screen.loaded()
        let image = try #require(Snapshot.render(screen.view(model), variant: variant, fits: false), "\(name) drew nothing")
        try Snapshot.match(image, name: name)
    }
}

/// The screens a change to the design package reaches most, each with fixed content, and each phase of the two Us
/// games. Onboarding's welcome draws drifting motes and the live hero cat, and the Shop's Today changes with the date,
/// so neither is here.
enum GalleryScreen: String, CaseIterable, Sendable {
    case inbox
    case inboxEmpty = "inbox-empty"
    case inboxFailed = "inbox-failed"
    case inboxLoading = "inbox-loading"
    case settings
    case whoKnowsIntro = "whoknows-intro"
    case whoKnowsAnswer = "whoknows-answer"
    case whoKnowsGuess = "whoknows-guess"
    case whoKnowsWaiting = "whoknows-waiting"
    case whoKnowsRevealed = "whoknows-revealed"
    case whoKnowsOffline = "whoknows-offline"
    case whoKnowsUnpaired = "whoknows-unpaired"
    case drawGuessGuess = "drawguess-guess"
    case drawGuessWaiting = "drawguess-waiting"
    case drawGuessDraw = "drawguess-draw"
    case drawGuessSolved = "drawguess-solved"
    case drawGuessOffline = "drawguess-offline"
    case drawGuessUnpaired = "drawguess-unpaired"
    case gameFeed = "game-feed"
    case gameResult = "game-result"
    case coins

    enum Loaded {
        case inbox(InboxModel)
        case whoKnows(WhoKnowsModel)
        case drawGuess(DrawGuessModel)
        case settings
        /// A mini-game's tray at the end of a meal, or its result.
        case game(finished: Bool)
        case coins(CoinPacksModel)
    }

    @MainActor func loaded() async -> Loaded {
        switch self {
        case .inbox: return await inbox(.items)
        case .inboxEmpty: return await inbox(.empty)
        case .inboxFailed: return await inbox(.failed)
        case .inboxLoading:
            // The fixture's first page never comes; the model stays loading while the page is drawn.
            let model = InboxFixture.model(.loading, now: Self.now)
            Task { await model.open() }
            while model.sheet != .loading { await Task.yield() }
            return .inbox(model)
        case .settings: return .settings
        case .whoKnowsIntro: return .whoKnows(await GameFixture.whoKnows(.intro))
        case .whoKnowsAnswer: return .whoKnows(await GameFixture.whoKnows(.answering))
        case .whoKnowsGuess: return .whoKnows(await GameFixture.whoKnows(.guessing))
        case .whoKnowsWaiting: return .whoKnows(await GameFixture.whoKnows(.waiting))
        case .whoKnowsRevealed: return .whoKnows(await GameFixture.whoKnows(.revealed))
        case .whoKnowsOffline: return .whoKnows(await GameFixture.whoKnows(.offline))
        case .whoKnowsUnpaired: return .whoKnows(await GameFixture.whoKnows(.unpaired))
        case .drawGuessGuess: return .drawGuess(await GameFixture.drawGuess(.guessing))
        case .drawGuessWaiting: return .drawGuess(await GameFixture.drawGuess(.waiting))
        case .drawGuessDraw: return .drawGuess(await GameFixture.drawGuess(.drawing))
        case .drawGuessSolved: return .drawGuess(await GameFixture.drawGuess(.solved))
        case .drawGuessOffline: return .drawGuess(await GameFixture.drawGuess(.offline))
        case .drawGuessUnpaired: return .drawGuess(await GameFixture.drawGuess(.unpaired))
        case .gameFeed: return .game(finished: false)
        case .gameResult: return .game(finished: true)
        case .coins:
            // The StoreKit build's packs, the first one paid while the server was out of reach.
            let model = CoinPacksModel(payments: GalleryStore()) {}
            await model.load()
            await model.buy(model.packs[0])
            return .coins(model)
        }
    }

    @MainActor private func inbox(_ scenario: InboxFixture.Scenario) async -> Loaded {
        let model = InboxFixture.model(scenario, now: Self.now)
        await model.open()
        return .inbox(model)
    }

    @MainActor @ViewBuilder func view(_ loaded: Loaded) -> some View {
        switch loaded {
        case .inbox(let model):
            NavigationStack {
                InboxSheet(model: model, state: HomeState(stores: .live(events: .none)), open: { _ in }, opensModel: false,
                           now: { Self.now })
            }
        case .whoKnows(let model):
            NavigationStack { WhoKnowsScreen(state: HomeState(stores: .live(events: .none)), model: model) }
                // The intro shows until this phone has seen the round; a store of its own keeps it unseen on every run.
                .defaultAppStorage(Self.freshStorage())
                // A reveal pops in on appear; drawn without animation it is always at rest.
                .transaction { $0.animation = nil }
        case .drawGuess(let model):
            NavigationStack { DrawGuessScreen(state: HomeState(stores: .live(events: .none)), model: model) }
                // The drawing replays over a few seconds; with Reduce Motion it is drawn whole at once.
                .environment(\._accessibilityReduceMotion, true)
                .transaction { $0.animation = nil }
        case .settings:
            NavigationStack { SettingsView(state: HomeState(stores: .live(events: .none))) {} }
        case .coins(let model):
            CoinsSheet(state: SellingHost(), packs: model)
        case .game(let finished):
            VStack {
                Spacer(minLength: 0)
                if finished {
                    ResultToast(result: GameResult(game: .feed, score: 90, grams: 40, tooMuch: false), again: {}, done: {})
                } else {
                    GameTray(
                        hint: "Sweep up the crumbs, or feed Tofu as it is",
                        bar: GameMeter(value: 1.1, label: "Bowl", detail: "42 / 38 g"), symbol: "fork.knife",
                        action: "Feed", assist: "Clean up", act: {}, assistAct: {})
                }
            }
            .padding(.bottom, Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ink.screen)
        }
    }

    /// An evening, so the Inbox's items of the last few hours are all today's.
    private static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 20))
        ?? Date(timeIntervalSince1970: 1_762_801_200)

    private static func freshStorage() -> UserDefaults {
        let suite = "gallery.screen"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite) ?? UserDefaults()
    }
}

/// The three packs at their US prices; a purchase is paid but not credited yet.
nonisolated private struct GalleryStore: Payments {
    func products() async throws(PaymentsError) -> [StampPack] {
        StampPackCatalog.standard.packs.map { definition in
            StampPack(id: definition.id, stamps: definition.stamps, displayName: "", description: "", displayPrice: "$\(definition.price)")
        }
    }

    func purchase(_ pack: StampPack) async throws(PaymentsError) -> PurchaseResult { .awaitingCredit }
    func restore() async throws(PaymentsError) -> StampLedger { .empty }
    func settleUnfinished() async {}
    func updates() -> AsyncStream<PaymentsUpdate> { AsyncStream { $0.finish() } }
}

/// A pair the server sells coins to, in a StoreKit build.
private final class SellingHost: ShopHost {
    private let home = HomeState(stores: .live(events: .none))

    var shop: ShopModel { home.shop }
    var shopCategory: ShopCategory {
        get { home.shopCategory }
        set { home.shopCategory = newValue }
    }
    var shopFocus: ShopFocus? {
        get { home.shopFocus }
        set { home.shopFocus = newValue }
    }
    var petName: String { "Tofu" }
    var remoteFlags: RemoteFlags { RemoteFlags(assignments: ["payments": "on"]) }
    var coatAvatarName: String { home.coatAvatarName }
    var storeIsMock: Bool { false }
    func isPlaced(_ itemID: String) -> Bool { false }
    func decorate(_ item: String?) {}
    func makeItemPreview() -> any ItemPreview { home.makeItemPreview() }
    func launchValue(_ key: String) -> String? { nil }
}
