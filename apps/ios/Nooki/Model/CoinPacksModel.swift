import Foundation
import Observation
import Payments
import WidgetBridge

/// The coin packs in the Coins sheet, sold through the build's store. The server credits a paid pack to the pair's
/// wallet, and the shop reads the new balance from there; nothing here counts coins.
@MainActor
@Observable
final class CoinPacksModel {
    enum Status: Equatable {
        case idle
        case buying(String)
        /// The coins arrive once someone else approves, such as a parent's Ask to Buy.
        case waiting
        case bought(coins: Int)
        case failed(String)
    }

    private(set) var packs: [StampPack] = []
    private(set) var status: Status = .idle
    @ObservationIgnored private let payments: (any Payments)?
    @ObservationIgnored private let credited: () async -> Void

    /// `credited` runs after the server took a pack, to read the wallet again.
    init(payments: (any Payments)?, credited: @escaping () async -> Void) {
        self.payments = payments
        self.credited = credited
    }

    /// The server's switch for selling coins (docs/payments.md).
    nonisolated static let flag = Experiment(key: "payments", variants: ["off", "on"])

    /// Packs on sale for this pair: only once the server turned `payments` on, whichever store the build carries, so a
    /// mock build that reaches testers or App Review sells nothing while the flag is off. Dev turns it on in the admin.
    nonisolated static func sells(_ flags: RemoteFlags) -> Bool {
        flags.variant(of: flag) == "on"
    }

    /// The smallest pack that covers `missing`, or the biggest when none does; nil when nothing is missing.
    nonisolated static func fit(for missing: Int, in packs: [StampPack]) -> StampPack? {
        guard missing > 0 else { return nil }
        let sorted = packs.sorted { $0.stamps < $1.stamps }
        return sorted.first { $0.stamps >= missing } ?? sorted.last
    }

    func load() async {
        guard let payments, packs.isEmpty else { return }
        packs = (try? await payments.products()) ?? []
    }

    func buy(_ pack: StampPack) async {
        guard let payments, status != .buying(pack.id) else { return }
        status = .buying(pack.id)
        do throws(PaymentsError) {
            switch try await payments.purchase(pack) {
            case .purchased(let credit):
                await credited()
                status = .bought(coins: credit.stamps)
            case .cancelled:
                status = .idle
            case .pending:
                status = .waiting
            }
        } catch {
            status = .failed(Self.message(error))
        }
    }

    nonisolated static func message(_ error: PaymentsError) -> String {
        switch error {
        case .notAllowed: "Purchases are turned off on this iPhone."
        case .unavailable: "Couldn't reach the store. Nothing was charged; try again."
        case .rejected, .failed, .unknownProduct: "That didn't go through. Nothing was charged."
        }
    }
}
