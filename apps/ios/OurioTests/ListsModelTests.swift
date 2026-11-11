import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Persistence
import Testing
import Transport
import UsInterface
import Wire
@testable import Billet

/// The pair's room as `ListsModel` sees it: the room's list rules in short, each change once per key.
private nonisolated final class FakeListRoom: @unchecked Sendable {
    var lists: [SharedList] = []
    var offline = false
    var keys: Set<String> = []
    var at = 1_700_000_000_000

    func sync(as user: String) -> ListSync {
        ListSync(
            fetch: { () throws(TransportError) in
                if self.offline { throw .network("offline") }
                return ListsResponse(lists: self.lists)
            },
            change: { request throws(TransportError) in
                if self.offline { throw .network("offline") }
                if self.keys.insert(request.change.key.rawValue).inserted {
                    try self.apply(request.change, by: UserId(user))
                }
                return ListsResponse(lists: self.lists)
            })
    }

    private func apply(_ change: ListCommand, by user: UserId) throws(TransportError) {
        at += 1
        switch change {
        case .createList(_, let list, let kind, let title, let icon):
            guard !lists.contains(where: { $0.id == list }) else { return }
            lists.append(SharedList(id: list, kind: kind, title: title, icon: icon, items: []))
        case .deleteList(_, let list):
            lists.removeAll { $0.id == list }
        case .addItem(_, let list, let item, let text, let details):
            try edit(list) { items in
                guard !items.contains(where: { $0.id == item }) else { return }
                items.append(Wire.ListItem(id: item, text: text, author: user, addedAt: at, details: details))
            }
        case .tickItem(_, let list, let item):
            try edit(list) { items in
                guard let i = items.firstIndex(where: { $0.id == item }), items[i].doneAt == nil else { return }
                let old = items[i]
                items[i] = Wire.ListItem(id: old.id, text: old.text, author: old.author, addedAt: old.addedAt,
                                         doneBy: user, doneAt: at, details: old.details, wants: old.wants)
            }
        case .deleteItem(_, let list, let item):
            try edit(list) { $0.removeAll { $0.id == item } }
        case .renameList, .editItem, .untickItem, .wantItem:
            Issue.record("not used here")
        }
    }

    private func edit(_ list: IdempotencyKey, _ body: (inout [Wire.ListItem]) -> Void) throws(TransportError) {
        guard let i = lists.firstIndex(where: { $0.id == list }) else { throw .api(.notFound) }
        var items = lists[i].items
        body(&items)
        let old = lists[i]
        lists[i] = SharedList(id: old.id, kind: old.kind, title: old.title, icon: old.icon, items: items)
    }
}

@MainActor
@Suite struct ListsModelTests {
    private let files = (0..<2).map { "Tests/\(UUID().uuidString)-lists-\($0).json" }
    private let users = ["L": "user-l", "M": "user-m"]

    private func phone(_ me: String, file: Int) -> (UsStore, ListsModel) {
        let us = UsStore(file: files[file])
        let users = users
        return (us, ListsModel(us: us) { (me, users) })
    }

    private func clean() {
        for file in files { try? FileManager.default.removeItem(at: SharedFile.url(file)) }
    }

    private func groceries(_ us: UsStore) -> [UsList] { us.lists.filter { $0.kind == .groceries } }

    @Test func eachPartnerSeesTheOthersItemsAndOneSetOfStarterLists() async {
        defer { clean() }
        let room = FakeListRoom()
        let (lena, lenas) = phone("L", file: 0)
        let (max, maxs) = phone("M", file: 1)
        await lenas.connect(room.sync(as: "user-l"))
        await maxs.connect(room.sync(as: "user-m"))
        #expect(room.lists.count == 3)
        #expect(max.lists.map(\.id) == lena.lists.map(\.id))

        let list = groceries(lena)[0].id
        lena.addItem("Oat milk", to: list, author: "L")
        await lenas.refresh()
        maxs.received(room.lists)
        #expect(max.list(list)?.items.map(\.text) == ["Oat milk"])
        #expect(max.list(list)?.items.first?.author == "L")

        max.toggleItem(max.list(list)!.items[0].id, in: list, by: "M")
        await maxs.refresh()
        await lenas.refresh()
        #expect(lena.list(list)?.items.first?.doneBy == "M")
        #expect(lena.pendingLists.isEmpty && max.pendingLists.isEmpty)
    }

    @Test func listsBothPhonesMadeBeforePairingAreBothKept() async {
        defer { clean() }
        let room = FakeListRoom()
        let (lena, lenas) = phone("L", file: 0)
        let (max, maxs) = phone("M", file: 1)
        lena.addItem("Milk", to: groceries(lena)[0].id, author: "L")
        let film = max.lists.first { $0.kind == .watch }!.id
        max.addItem("Paddington", to: film, author: "M")
        max.toggleItem(max.list(film)!.items[0].id, in: film, by: "M")

        await lenas.connect(room.sync(as: "user-l"))
        await maxs.connect(room.sync(as: "user-m"))
        await lenas.refresh()

        // Max's empty groceries and travel starters stay out; his watch list has an item, so it joins.
        #expect(lena.lists.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.groceries, .travel, .watch, .watch])
        #expect(lena.list(film)?.items.first?.doneBy == "M")
        #expect(lena.lists == max.lists)
    }

    @Test func aChangeMadeOfflineShowsAtOnceAndReachesTheRoomLater() async {
        defer { clean() }
        let room = FakeListRoom()
        let (lena, lenas) = phone("L", file: 0)
        await lenas.connect(room.sync(as: "user-l"))
        let list = groceries(lena)[0].id

        room.offline = true
        lena.addItem("Pears", to: list, author: "L")
        await lenas.refresh()
        #expect(lena.list(list)?.items.map(\.text) == ["Pears"])
        #expect(lena.pendingLists.count == 1)
        #expect(room.lists.first { $0.id.rawValue == list.uuidString }?.items.isEmpty == true)

        room.offline = false
        await lenas.refresh()
        #expect(lena.pendingLists.isEmpty)
        #expect(room.lists.first { $0.id.rawValue == list.uuidString }?.items.map(\.text) == ["Pears"])
        #expect(lena.list(list)?.items.map(\.text) == ["Pears"])
    }

    @Test func aChangeToAListThePartnerDeletedIsDropped() async {
        defer { clean() }
        let room = FakeListRoom()
        let (lena, lenas) = phone("L", file: 0)
        await lenas.connect(room.sync(as: "user-l"))
        let list = groceries(lena)[0].id

        room.lists.removeAll { $0.id.rawValue == list.uuidString }
        lena.addItem("Pears", to: list, author: "L")
        await lenas.refresh()
        #expect(lena.pendingLists.isEmpty)
        #expect(lena.list(list) == nil)
    }

    @Test func aWidgetsTickWaitsInTheFileForTheApp() async {
        defer { clean() }
        let room = FakeListRoom()
        let (lena, lenas) = phone("L", file: 0)
        await lenas.connect(room.sync(as: "user-l"))
        let list = groceries(lena)[0].id
        lena.addItem("Pears", to: list, author: "L")
        await lenas.refresh()

        let widget = UsStore(file: files[0])
        widget.setItem(widget.list(list)!.items[0].id, in: list, done: true)
        lena.reload()
        #expect(lena.pendingLists.count == 1)
        await lenas.refresh()
        #expect(room.lists.first { $0.id.rawValue == list.uuidString }?.items.first?.doneBy == UserId("user-l"))
    }

    @Test func leavingThePairKeepsTheListsAsThePhonesOwn() async {
        defer { clean() }
        let room = FakeListRoom()
        let (lena, lenas) = phone("L", file: 0)
        await lenas.connect(room.sync(as: "user-l"))
        let before = lena.lists
        await lenas.connect(nil)
        #expect(!lena.followsRoomLists)
        #expect(lena.lists == before)
        lena.addItem("Pears", to: groceries(lena)[0].id, author: "L")
        #expect(lena.pendingLists.isEmpty)
    }

    @Test func aFileFromBeforeSharedListsStillReads() throws {
        defer { clean() }
        let url = SharedFile.url(files[0])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"""
        {"lists":[{"id":"00000000-0000-4000-8000-0000000000C1","kind":"groceries","title":"Groceries",
        "icon":{"symbol":"basket.fill","tint":"sage"},"items":[{"id":"00000000-0000-4000-8000-0000000000C2",
        "text":"Milk","author":"L","added":0}]}],"wishes":[],"loves":{},"events":[],"planned":[],"swipes":{}}
        """#.utf8).write(to: url)
        let us = UsStore(file: files[0])
        #expect(us.lists.first?.items.first?.text == "Milk")
        #expect(us.lists.first?.items.first?.wants == [])
        #expect(!us.followsRoomLists)
    }
}
