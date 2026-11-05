import Foundation
import Wire

extension HomeState {
    /// The ink buy still inside its Undo window: the server hasn't heard of it yet, so its spend and its ink are the
    /// phone's alone.
    private var pendingInk: Purchase? {
        guard let lastPurchase, lastPurchase.kind == .ink, lastPurchase.canUndo(at: .now) else { return nil }
        return lastPurchase
    }

    /// Takes the server's catalog and the inks the pair owns there.
    func apply(_ response: InksResponse) {
        let catalog = response.inks.compactMap(PaletteInk.init)
        if !catalog.isEmpty { inks = catalog }
        own(response.owned)
    }

    /// The pair's balance as the server keeps it, less an ink buy it hasn't been told of yet.
    func apply(balance: Int) {
        let pending = pendingInk?.cost ?? 0
        wallet.update { $0.coins = max(0, balance - pending) }
    }

    func apply(_ response: BuyResponse) {
        own(response.owned)
        apply(balance: response.balance)
    }

    /// The server's owned inks replace the phone's, except one bought inside the Undo window.
    private func own(_ inks: [InkId]) {
        let pending = Set(pendingInk?.added ?? [])
        wallet.update {
            $0.owned = $0.owned.filter { !PaletteInk.isInk($0) || pending.contains($0) }
                .union(inks.map(\.rawValue))
        }
    }
}
