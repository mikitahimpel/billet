import Foundation
import MomentsInterface
import OurioShared
import Transport
import UsInterface
import Wire

/// Keeps the Us tab's lists in step with the pair's room while the phone is paired. Each change made here shows at
/// once and waits in `UsStore.pendingLists` until the room answers it; the room's lists, from an answer or its socket,
/// are the truth under whatever still waits.
final class ListsModel {
    typealias Members = GiftsModel.Members

    private let us: UsStore
    private let members: Members
    private var sync: ListSync?
    /// The send under way; another send waits for it, since it takes each change as it comes.
    private var sending: Task<Void, Never>?

    init(us: UsStore, members: @escaping Members) {
        self.us = us
        self.members = members
        us.onListChange = { [weak self] in
            Task { await self?.send() }
        }
    }

    /// Follows the pair's room, or, with nil, keeps the lists as the phone has them, as its own.
    func connect(_ sync: ListSync?) async {
        self.sync = sync
        guard let sync else { return us.leaveRoomLists() }
        guard let answer = try? await sync.fetch() else { return }
        mirror(answer.lists)
        await send()
    }

    /// Reads the pair's room again and sends what waits, a widget's ticks included.
    func refresh() async {
        guard let sync else { return }
        await connect(sync)
    }

    /// The room's lists, as its socket pushed them after a change.
    func received(_ lists: [SharedList]) {
        guard sync != nil else { return }
        mirror(lists)
    }

    /// Sends what waits, oldest first. Offline, it stops and waits for the next change or refresh; a change the room
    /// refuses, such as one to a list the partner deleted, is dropped.
    private func send() async {
        if let sending { return await sending.value }
        guard let sync else { return }
        let task = Task { await drain(sync) }
        sending = task
        await task.value
        sending = nil
    }

    private func drain(_ sync: ListSync) async {
        while let next = us.pendingLists.first {
            let request = ChangeListRequest(change: next.change, utcOffsetSeconds: ShopModel.utcOffset(at: next.at))
            do throws(TransportError) {
                let answer = try await sync.change(request)
                us.listChangeDone(next.change.key, room: lists(answer.lists))
            } catch {
                switch error {
                case .api(.unauthorized), .api(.unavailable), .network, .status, .maintenance, .encoding, .decoding:
                    return
                case .api:
                    us.listChangeDone(next.change.key, room: nil)
                }
            }
        }
    }

    private func mirror(_ room: [SharedList]) {
        guard let me = members()?.me, let lists = lists(room) else { return }
        us.mirrorLists(lists, me: me)
    }

    /// The room's lists with monograms for user ids, newest item first as the Us tab keeps them.
    private func lists(_ room: [SharedList]) -> [UsList]? {
        guard let (_, users) = members() else { return nil }
        let monograms = Dictionary(users.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        let monogram = { (user: UserId) in monograms[user.rawValue] ?? "" }
        return room.compactMap { list in
            guard let id = UUID(list.id) else { return nil }
            let items = list.items.reversed().compactMap { item -> ListItem? in
                guard let itemID = UUID(item.id) else { return nil }
                var app = ListItem(id: itemID, text: item.text, author: monogram(item.author),
                                   added: Self.date(item.addedAt))
                app.done = item.doneAt.map(Self.date)
                app.doneBy = item.doneBy.map(monogram)
                app.details = item.details
                app.wants = item.wants.map(monogram)
                return app
            }
            return UsList(id: id, kind: ListKind(list.kind), title: list.title, icon: UsGlyph(list.icon), items: items)
        }
    }

    private static func date(_ millis: Int) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }
}
