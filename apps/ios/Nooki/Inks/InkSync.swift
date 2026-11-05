import Foundation
import Transport
import Wire

/// The shop's inks and the pair's coins as the server keeps them. The server has no undo, so an ink buy waits out
/// its Undo window on the phone and is sent only if it still stands.
struct InkSync {
    let api: APIClient
    var undoWindow: Duration = .seconds(Purchase.undoWindow)

    /// The catalog, what the pair owns and the balance. A failure keeps what the phone has.
    func refresh(_ state: HomeState) async {
        if let inks = try? await api.listInks() { state.apply(inks) }
        if let coins = try? await api.getCoins() { state.apply(balance: coins.balance) }
    }

    /// Sends `purchase` once Undo is over, under one key for every retry. Undone by then, nothing is sent; a
    /// refusal puts the server's balance and inks back.
    func settle(_ purchase: Purchase, _ state: HomeState) async {
        guard purchase.kind == .ink else { return }
        try? await Task.sleep(for: undoWindow)
        for id in purchase.added where state.owned.contains(id) {
            let request = BuyRequest(id: IdempotencyKey("\(purchase.id.uuidString)-\(id)"), item: InkId(id))
            do throws(TransportError) {
                state.apply(try await send(request))
            } catch {
                await refresh(state)
            }
        }
    }

    /// One retry when the network drops, with the same key so the ink is bought once.
    private func send(_ request: BuyRequest) async throws(TransportError) -> BuyResponse {
        do {
            return try await api.buyItem(request)
        } catch .network(_) {
            try? await Task.sleep(for: .seconds(2))
            return try await api.buyItem(request)
        }
    }
}
