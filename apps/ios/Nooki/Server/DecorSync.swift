import DecorInterface
import FeatureDecor
import FeatureShop
import Foundation
import Transport
import Wire

/// Keeps the pair's layout in step with the room on the server: what the player changes goes up as `Place` and
/// `Unplace`, each under its own id, and what the room says (a partner's change, or a refusal) comes back as
/// the layout. A phone that is offline keeps the change on itself and the server's next word replaces it.
@MainActor
final class DecorSync {
    /// Nil until the pair's room is followed.
    var client: () -> ShopClient? = { nil }
    weak var store: DecorStore?

    /// The server's layout as last heard.
    private var known: [Placement] = []
    private var sending = false
    private var dirty = false

    /// The room's layout arrived, from a read or a push. A room that has none yet takes this phone's.
    func heard(_ wire: [RoomPlacement]?) {
        guard let wire, let store else { return }
        known = DecorSyncPlan.placements(wire)
        if known.isEmpty, !store.state.book.layout.placements.isEmpty {
            push(store.state.book.layout)
        } else {
            store.send(.remote(known))
        }
    }

    /// The player changed the layout.
    func push(_ layout: DecorLayout) {
        guard client() != nil else { return }
        dirty = true
        guard !sending else { return }
        sending = true
        Task { await drain() }
    }

    private func drain() async {
        defer { sending = false }
        while dirty, let store, let client = client() {
            dirty = false
            let changes = DecorSyncPlan.changes(from: known, to: store.state.book.layout.placements)
            for change in changes {
                do {
                    let answer = try await client.changeLayout(LayoutRequest(id: .make(), change: change))
                    known = DecorSyncPlan.placements(answer.shop.layout ?? [])
                } catch {
                    if case .api(.layoutRefused) = error { await reread(client) }
                    // Offline: the change stays on this phone; the room's next word replaces it.
                    break
                }
            }
        }
    }

    /// The room refused a change: take its layout.
    private func reread(_ client: ShopClient) async {
        guard let shop = try? await client.fetch() else { return }
        known = DecorSyncPlan.placements(shop.layout ?? [])
        store?.send(.remote(known))
    }
}
