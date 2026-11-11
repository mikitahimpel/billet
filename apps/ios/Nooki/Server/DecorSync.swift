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
    private var knownStowed: Set<String>?
    private var sending = false
    private var dirty = false

    /// The room's layout arrived, from a read or a push. A room that has none yet takes this phone's.
    func heard(_ wire: [RoomPlacement]?, stowed: [RoomItemId]?) {
        guard let wire, let store else { return }
        known = DecorSyncPlan.placements(wire)
        knownStowed = DecorSyncPlan.stowed(stowed)
        let local = store.state.book.layout
        if known.isEmpty, knownStowed?.isEmpty != false, !local.placements.isEmpty || !local.stowed.isEmpty {
            push(local)
        } else {
            store.send(.remote(known, stowed: knownStowed))
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
            let server = DecorLayout().replacing(placements: known, stowed: knownStowed ?? [])
            let changes = DecorSyncPlan.changes(from: server.allPlacements, to: store.state.book.layout.allPlacements)
            for change in changes {
                do {
                    let answer = try await client.changeLayout(LayoutRequest(id: .make(), change: change))
                    known = DecorSyncPlan.placements(answer.shop.layout ?? [])
                    knownStowed = DecorSyncPlan.stowed(answer.shop.stowed)
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
        knownStowed = DecorSyncPlan.stowed(shop.stowed)
        store?.send(.remote(known, stowed: knownStowed))
    }
}
