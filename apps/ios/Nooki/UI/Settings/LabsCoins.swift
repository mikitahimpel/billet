#if DEBUG || LABS_YES
import BilletKit
import Design
import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Payments
import SwiftUI
import Transport
import UsInterface
import Wire

/// Labs → Coins: gives the pair coins for testing through the dev server's mock store (`POST /v1/purchases/mock`),
/// which credits the pair's wallet like a bought pack. A server without the mock store refuses it.
nonisolated enum LabsCoinsMachine: Machine {
    static let amounts = [100, 500, 5000]

    enum Failure: Equatable, Sendable {
        /// The route is a 404: not the dev server, or no partner yet.
        case noMockStore
        case unreachable
        case refused
    }

    enum State: Equatable, Sendable {
        case idle
        case adding(Int)
        case added(Int)
        case failed(Failure)
    }

    enum Event: Equatable, Sendable {
        case tapped(Int)
        case credited
        case failed(Failure)
    }

    enum Output: Equatable, Sendable {
        /// Credit `amount` coins, then read the shop again; answers `.credited` or `.failed`.
        case credit(Int)
    }

    static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
        switch (state, event) {
        case (.idle, .tapped(let amount)), (.added, .tapped(let amount)), (.failed, .tapped(let amount)):
            return (.adding(amount), [.credit(amount)])

        case (.adding(let amount), .credited):
            return (.added(amount), [])

        case (.adding, .failed(let failure)):
            return (.failed(failure), [])

        case (.adding, .tapped),
            (.idle, .credited), (.idle, .failed),
            (.added, .credited), (.added, .failed),
            (.failed, .credited), (.failed, .failed):
            return (state, [])
        }
    }

    /// The mock store sells only the catalog's packs, so `amount` goes out as packs, the biggest first; nil when they
    /// can't make it exactly.
    static func packs(for amount: Int, in packs: [StampPackCatalog.Definition]) -> [StampPackCatalog.Definition]? {
        var left = amount
        var chosen: [StampPackCatalog.Definition] = []
        for pack in packs.sorted(by: { $0.stamps > $1.stamps }) where pack.stamps > 0 {
            chosen += Array(repeating: pack, count: left / pack.stamps)
            left %= pack.stamps
        }
        return left == 0 && !chosen.isEmpty ? chosen : nil
    }

    static func failure(_ error: TransportError) -> Failure {
        switch error {
        case .api(.notFound): .noMockStore
        case .api(.unavailable), .network, .status, .maintenance: .unreachable
        case .api(.unauthorized), .api(.invalidPurchase), .api(.invalidRequest), .api(.invalidInvite),
             .api(.alreadyPaired), .api(.appleIdInUse), .api(.inkNotOwned), .api(.notEnoughCoins),
             .api(.alreadyOwned), .api(.collectionIncomplete), .api(.giftTaken), .api(.bonusTaken),
             .api(.catNotAdopted), .api(.streakNotRestorable), .api(.priceChanged), .api(.layoutRefused), .encoding, .decoding:
            .refused
        }
    }

    static func message(_ failure: Failure) -> String {
        switch failure {
        case .noMockStore:
            "This server has no mock store, so it can't add coins. Only the dev server has one, for a paired account"
                + (AppPayments.isMock ? "." : "; this StoreKit build may be pointed at another server.")
        case .unreachable: "Couldn't reach the server. Try again in a moment."
        case .refused: "The server refused the coins."
        }
    }
}

enum LabsCoins {
    /// `credit` posts one mock purchase per pack; `refresh` reads the shop's balance again, also after a failure
    /// that came after some packs were credited.
    @MainActor
    static func store(
        catalog: StampPackCatalog = .standard,
        credit: @escaping @Sendable (MockPurchaseRequest) async throws(TransportError) -> Void,
        refresh: @escaping @Sendable () async -> Void
    ) -> Store<LabsCoinsMachine> {
        Store(initial: .idle) { output in
            switch output {
            case .credit(let amount):
                guard let packs = LabsCoinsMachine.packs(for: amount, in: catalog.packs) else { return .failed(.refused) }
                var failure: LabsCoinsMachine.Failure?
                do throws(TransportError) {
                    for pack in packs {
                        try await credit(MockPurchaseRequest(
                            productId: pack.id, transactionId: "mock-labs-\(UUID().uuidString)", kind: .purchase))
                    }
                } catch {
                    failure = LabsCoinsMachine.failure(error)
                }
                await refresh()
                return failure.map { .failed($0) } ?? .credited
            }
        }
    }
}

/// The rows Labs shows for coins: the wallet's balance and the amounts to add.
struct LabsCoinsRows: View {
    let shop: ShopModel
    @State private var store: Store<LabsCoinsMachine>
    @State private var confirmations = 0

    init(shop: ShopModel, purchases: PurchasesClient) {
        self.shop = shop
        _store = State(initialValue: LabsCoins.store(
            credit: { (request) async throws(TransportError) in _ = try await purchases.mockPurchase(request) },
            refresh: { await shop.refresh() }))
    }

    var body: some View {
        Row("Coins", detail: detail, symbol: "dollarsign.circle.fill", tint: UsTint.honey.color) {
            if case .adding = store.state { ProgressView() }
        }
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                ForEach(LabsCoinsMachine.amounts, id: \.self) { amount in
                    PriceButton(amount, label: "Add \(amount) coins") { store.send(.tapped(amount)) }
                }
            }
            .disabled(isAdding)
            if case .failed(let failure) = store.state {
                ErrorLine(LabsCoinsMachine.message(failure))
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .haptic(.confirmed, trigger: confirmations)
        .onChange(of: store.state) { _, state in
            if case .added = state { confirmations += 1 }
        }
    }

    private var isAdding: Bool {
        if case .adding = store.state { true } else { false }
    }

    private var detail: String {
        let balance = shop.coins.formatted()
        switch store.state {
        case .idle, .failed: return "\(balance) in the wallet"
        case .adding(let amount): return "Adding \(amount.formatted())…"
        case .added(let amount): return "\(balance) in the wallet, \(amount.formatted()) added"
        }
    }
}
#endif
