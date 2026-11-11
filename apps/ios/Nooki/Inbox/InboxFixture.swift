#if DEBUG
import FeatureInbox
import Foundation
import Transport
import Wire

/// A day and a half of a pair's activity, for previews, tests and `-inboxFixture YES` screenshots.
enum InboxFixture {
    static func items(now: Date = .now) -> [ActivityItem] {
        func at(_ minutesAgo: Double) -> Int { Int((now.timeIntervalSince1970 - minutesAgo * 60) * 1000) }
        return [
            ActivityItem(id: "cat:fed-1", at: at(4), actor: .partner, event: .catFed(grams: 40), target: .cat),
            ActivityItem(
                id: "note:d-1", at: at(25), actor: .partner, event: .noteSent(note: NoteId("d-1"), kind: "Drawing"),
                target: .moments(NoteId("d-1"))),
            ActivityItem(id: "cat:nap-1", at: at(70), actor: .cat, event: .catSlept, target: .cat),
            ActivityItem(
                id: "cat:water-1", at: at(150), actor: .partner, event: .plantWatered(plant: "monstera"),
                target: .plant("monstera")),
            ActivityItem(
                id: "coin:buy-1", at: at(190), actor: .me, event: .purchased(offer: nil, items: ["lamp"], coins: 140),
                target: .shopItem("lamp")),
            ActivityItem(id: "streak:12", at: at(60 * 20), actor: .partner, event: .streakReached(days: 12)),
            ActivityItem(
                id: "cat:game-1", at: at(60 * 26), actor: .partner,
                event: .catGamePlayed(game: "feeding-scale", score: 92, won: true), target: .cat),
            ActivityItem(
                id: "note:t-1", at: at(60 * 30), actor: .me, event: .noteSent(note: NoteId("t-1"), kind: "Text"),
                target: .note(NoteId("t-1"))),
        ]
    }

    enum Scenario {
        case items, empty, failed, loading
    }

    /// A model that answers from the fixture: the newest three are unread until marked.
    static func model(_ scenario: Scenario = .items, now: Date = .now) -> InboxModel {
        let items = scenario == .items ? items(now: now) : []
        return InboxModel(
            list: { (before) async throws(TransportError) in
                switch scenario {
                case .failed: throw TransportError.network("offline")
                case .loading:
                    try? await Task.sleep(for: .seconds(3600))
                    throw TransportError.network("cancelled")
                case .items, .empty: return ActivityResponse(items: before == nil ? items : [], unread: items.isEmpty ? 0 : 3)
                }
            },
            markRead: { (_) async throws(TransportError) in ActivityUnreadResponse(unread: 0) },
            timeout: scenario == .loading ? .seconds(3600) : .seconds(15))
    }
}

extension ActivityItem {
    /// A fixture item with the cursor the server would give it: `at` padded to 16 digits, `~`, the id.
    nonisolated init(
        id: String, at: Int, actor: ActivityActor, event: ActivityEvent, target: ActivityTarget? = nil
    ) {
        let digits = String(at)
        let cursor = String(repeating: "0", count: max(0, 16 - digits.count)) + digits + "~" + id
        self.init(id: id, at: at, actor: actor, event: event, target: target, cursor: cursor)
    }
}
#endif
