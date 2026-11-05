import Foundation
import Observation
import Transport
import Wire

/// The pair's activity, newest first, for the Inbox: loads pages from the server, keeps the unread count for the
/// header's badge, and marks what was seen as read for this person.
@MainActor
@Observable
final class InboxModel {
    enum Phase: Equatable {
        case idle, loading, loaded
        /// The server couldn't be reached or answered with an error.
        case failed
        /// No partner yet: the server has no room to read from.
        case unpaired
    }

    private(set) var items: [ActivityItem] = []
    private(set) var unread = 0
    private(set) var phase: Phase = .idle
    /// Items that were unread when the Inbox was last opened; they stay marked until it is opened again.
    private(set) var fresh: Set<String> = []
    private(set) var next: String?

    @ObservationIgnored private let list: @Sendable (String?) async throws(TransportError) -> ActivityResponse
    @ObservationIgnored private let markRead:
        @Sendable (MarkActivityReadRequest) async throws(TransportError) -> ActivityUnreadResponse

    init(
        list: @escaping @Sendable (String?) async throws(TransportError) -> ActivityResponse,
        markRead: @escaping @Sendable (MarkActivityReadRequest) async throws(TransportError) -> ActivityUnreadResponse
    ) {
        self.list = list
        self.markRead = markRead
    }

    convenience init(api: APIClient) {
        self.init(list: api.listActivity, markRead: api.markActivityRead)
    }

    /// The first page again, then everything on it is read. Used when the Inbox opens and on pull to refresh.
    func open() async {
        if items.isEmpty { phase = .loading }
        do {
            let page = try await list(nil)
            items = page.items
            next = page.next
            unread = page.unread
            fresh = Self.unreadIDs(in: page.items, count: page.unread)
            phase = .loaded
        } catch {
            phase = error == .api(.notFound) ? .unpaired : .failed
            return
        }
        await readAll()
    }

    /// The page after the last one shown.
    func loadMore() async {
        guard let next, phase == .loaded else { return }
        guard let page = try? await list(next) else { return }
        let known = Set(items.map(\.id))
        items += page.items.filter { !known.contains($0.id) }
        self.next = page.next
    }

    /// The count the room socket reports when the partner adds something or this person reads elsewhere.
    func unreadChanged(_ count: Int) {
        unread = count
    }

    /// Only the count, for the badge while the Inbox is closed.
    func refreshCount() async {
        guard let page = try? await list(nil) else { return }
        unread = page.unread
    }

    private func readAll() async {
        guard unread > 0, let newest = items.first else { return }
        if let answer = try? await markRead(MarkActivityReadRequest(upTo: newest.cursor)) {
            unread = answer.unread
        }
    }

    /// The newest `count` items someone else made: the server counts only those above the read mark, and they are
    /// always the newest.
    static func unreadIDs(in items: [ActivityItem], count: Int) -> Set<String> {
        Set(items.lazy.filter { $0.actor != .me }.prefix(count).map(\.id))
    }
}
