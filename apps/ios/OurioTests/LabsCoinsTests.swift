#if DEBUG || LABS_YES
import Foundation
import Payments
import Testing
import Transport
import Wire
@testable import Billet

@Suite struct LabsCoinsTests {
    typealias Machine = LabsCoinsMachine

    @Test(arguments: [Machine.State.idle, .added(100), .failed(.noMockStore)])
    func aTapCreditsTheAmount(from state: Machine.State) {
        let (next, outputs) = Machine.transition(state, .tapped(500))
        #expect(next == .adding(500))
        #expect(outputs == [.credit(500)])
    }

    @Test func theAnswerEndsTheAdding() {
        #expect(Machine.transition(.adding(500), .credited) == (.added(500), []))
        #expect(Machine.transition(.adding(500), .failed(.unreachable)) == (.failed(.unreachable), []))
    }

    @Test(arguments: [
        (Machine.State.adding(100), Machine.Event.tapped(5000)),
        (.idle, .credited), (.idle, .failed(.refused)),
        (.added(100), .credited), (.added(100), .failed(.refused)),
        (.failed(.refused), .credited), (.failed(.refused), .failed(.unreachable)),
    ])
    func rejectedEventsChangeNothing(state: Machine.State, event: Machine.Event) {
        let (next, outputs) = Machine.transition(state, event)
        #expect(next == state)
        #expect(outputs.isEmpty)
    }

    @Test func amountsGoOutAsTheCatalogsPacks() throws {
        let packs = StampPackCatalog.standard.packs
        let coins = { (amount: Int) in Machine.packs(for: amount, in: packs)?.map(\.stamps) }
        #expect(coins(100) == [100])
        #expect(coins(500) == [100, 100, 100, 100, 100])
        #expect(coins(5000) == [1200, 1200, 1200, 1200, 100, 100])
        #expect(coins(50) == nil)
        #expect(coins(0) == nil)
        for amount in Machine.amounts {
            #expect(try #require(Machine.packs(for: amount, in: packs)).map(\.stamps).reduce(0, +) == amount)
        }
    }

    @Test func aServerWithoutTheMockStoreSaysSo() {
        #expect(Machine.failure(.api(.notFound)) == .noMockStore)
        #expect(Machine.failure(.network("offline")) == .unreachable)
        #expect(Machine.failure(.api(.invalidPurchase)) == .refused)
        #expect(Machine.message(.noMockStore).contains("no mock store"))
    }

    @Test @MainActor func aTapPostsEachPackThenReadsTheShop() async {
        let log = Log()
        let store = LabsCoins.store(
            credit: { request in await log.add(request) },
            refresh: { await log.refreshed() })
        store.send(.tapped(500))
        await store.settled()
        #expect(store.state == .added(500))
        let requests = await log.requests
        #expect(requests.count == 5)
        #expect(requests.allSatisfy { $0.kind == .purchase && $0.transactionId.hasPrefix("mock-labs-") })
        #expect(Set(requests.map(\.transactionId)).count == 5)
        #expect(await log.refreshes == 1)
    }

    @Test @MainActor func aRefusalStillReadsTheShop() async {
        let log = Log()
        let store = LabsCoins.store(
            credit: { (_) async throws(TransportError) in throw .api(.notFound) },
            refresh: { await log.refreshed() })
        store.send(.tapped(100))
        await store.settled()
        #expect(store.state == .failed(.noMockStore))
        #expect(await log.refreshes == 1)
    }
}

private actor Log {
    private(set) var requests: [MockPurchaseRequest] = []
    private(set) var refreshes = 0

    func add(_ request: MockPurchaseRequest) { requests.append(request) }
    func refreshed() { refreshes += 1 }
}
#endif
