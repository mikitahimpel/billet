import Payments
import Testing
import WidgetBridge
import Wire
@testable import Billet

@Suite struct CoinsSheetTests {
    @Test func aMockBuildSellsPacksWhateverTheFlagSays() {
        #expect(CoinPacksModel.sells(RemoteFlags(), mockStore: true))
        #expect(CoinPacksModel.sells(RemoteFlags(assignments: ["payments": "off"]), mockStore: true))
    }

    @Test func aStoreKitBuildSellsPacksOnlyWhenTheServerDoes() {
        #expect(!CoinPacksModel.sells(RemoteFlags(), mockStore: false))
        #expect(!CoinPacksModel.sells(RemoteFlags(assignments: ["payments": "off"]), mockStore: false))
        #expect(!CoinPacksModel.sells(RemoteFlags(assignments: ["payments": "maybe"]), mockStore: false))
        #expect(CoinPacksModel.sells(RemoteFlags(assignments: ["payments": "on"]), mockStore: false))
    }

    @Test @MainActor func aBoughtPackReadsTheWalletAgain() async throws {
        let reads = Counter()
        let model = CoinPacksModel(payments: FakePayments(result: .succeed)) { reads.count += 1 }
        await model.load()
        #expect(model.packs.map(\.stamps) == [100, 550, 1200])
        await model.buy(try #require(model.packs.first))
        #expect(model.status == .bought(coins: 100))
        #expect(reads.count == 1)
    }

    @Test @MainActor func aFailedOrCancelledBuyChangesNothing() async throws {
        let reads = Counter()
        let failing = CoinPacksModel(payments: FakePayments(result: .fail(.unavailable))) { reads.count += 1 }
        await failing.load()
        await failing.buy(try #require(failing.packs.first))
        #expect(failing.status == .failed(CoinPacksModel.message(.unavailable)))

        let cancelled = CoinPacksModel(payments: FakePayments(result: .cancel)) { reads.count += 1 }
        await cancelled.load()
        await cancelled.buy(try #require(cancelled.packs.first))
        #expect(cancelled.status == .idle)
        #expect(reads.count == 0)
    }

    @Test @MainActor func aStoreThatCantBeReachedShowsAnEmptyShelfAndCanTryAgain() async {
        let down = CoinPacksModel(payments: FakePayments(result: .succeed, shelf: .fail(.unavailable))) {}
        #expect(down.shelf == .loading)
        await down.load()
        #expect(down.shelf == .unavailable)
        #expect(down.packs.isEmpty)

        let empty = CoinPacksModel(payments: FakePayments(result: .succeed, shelf: .empty)) {}
        await empty.load()
        #expect(empty.shelf == .unavailable)

        let none = CoinPacksModel(payments: nil) {}
        await none.load()
        #expect(none.shelf == .unavailable)
    }

    @Test func theSmallestPackThatCoversTheGapIsTheOneShown() {
        let packs = StampPackCatalog.standard.packs.map(StampPackCatalog.standard.pack)
        #expect(CoinPacksModel.fit(for: 0, in: packs) == nil)
        #expect(CoinPacksModel.fit(for: 40, in: packs)?.stamps == 100)
        #expect(CoinPacksModel.fit(for: 100, in: packs)?.stamps == 100)
        #expect(CoinPacksModel.fit(for: 101, in: packs)?.stamps == 550)
        #expect(CoinPacksModel.fit(for: 5000, in: packs)?.stamps == 1200)
    }

    @Test func theServerAnswersMapToWhatTheBuyerCanDo() {
        #expect(PaymentsServer.mapped(.api(.invalidPurchase)) == .rejected)
        #expect(PaymentsServer.mapped(.api(.notFound)) == .unavailable)
        #expect(PaymentsServer.mapped(.network("offline")) == .unavailable)
    }

    @Test func anEntryReadsAsWhatItWasFor() {
        let spend = CoinLine(CoinEntry(id: "spend:k", kind: .spend, amount: -60, ref: "yarn", at: 0))
        #expect(spend.title == Catalog.item("yarn")?.name)
        #expect(spend.amount == "−60")
        #expect(!spend.isGain)
        let wish = CoinLine(CoinEntry(id: "earn:wish:w1", kind: .earn, amount: 20, ref: "w1", at: 0))
        #expect(wish.title == "A wish came true")
        #expect(wish.amount == "+20")
        #expect(CoinLine(CoinEntry(id: "earn:k", kind: .earn, amount: 5, ref: "k", at: 0)).title == "Notes and care")
        #expect(CoinLine(CoinEntry(id: "gift:welcome", kind: .gift, amount: 560, ref: "welcome", at: 0)).title
            == "Welcome coins")
        #expect(CoinLine(CoinEntry(id: "spend:t", kind: .spend, amount: -10, ref: "treat", at: 0)).title == "A treat")
    }
}

@MainActor private final class Counter {
    var count = 0
}

nonisolated private struct FakePayments: Payments {
    enum Outcome: Sendable {
        case succeed
        case cancel
        case fail(PaymentsError)
    }

    enum Shelf: Sendable {
        case standard
        case empty
        case fail(PaymentsError)
    }

    let result: Outcome
    var shelf = Shelf.standard

    func products() async throws(PaymentsError) -> [StampPack] {
        switch shelf {
        case .standard: StampPackCatalog.standard.packs.map(StampPackCatalog.standard.pack)
        case .empty: []
        case .fail(let error): throw error
        }
    }

    func purchase(_ pack: StampPack) async throws(PaymentsError) -> PurchaseResult {
        switch result {
        case .succeed:
            .purchased(StampCredit(
                entryID: "purchase:t1", transactionID: "t1", productID: pack.id, stamps: pack.stamps,
                serverBalance: pack.stamps, duplicate: false))
        case .cancel: .cancelled
        case .fail(let error): throw error
        }
    }

    func restore() async throws(PaymentsError) -> StampLedger { StampLedger(balance: 0, entries: []) }

    func updates() -> AsyncStream<PaymentsUpdate> { AsyncStream { $0.finish() } }
}
