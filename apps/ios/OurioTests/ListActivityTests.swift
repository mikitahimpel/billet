import Foundation
import MomentsInterface
import OurioShared
import Testing
import UsInterface
@testable import Billet

@Suite struct ListActivityTests {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func list(_ kind: ListKind, _ items: [ListItem] = []) -> UsList {
        UsList(kind: kind, title: kind.defaultTitle, icon: kind.icon, items: items)
    }

    private func item(_ author: String, _ added: TimeInterval, done: TimeInterval? = nil, by: String? = nil) -> ListItem {
        var item = ListItem(text: "x", author: author, added: now.addingTimeInterval(added))
        item.done = done.map(now.addingTimeInterval)
        item.doneBy = by
        return item
    }

    @Test func countsThePartnersAddsThatDay() {
        let groceries = list(.groceries, [item("M", -60), item("M", -120), item("L", -10), item("M", -2 * 86_400)])
        #expect(groceries.latestChange(by: "M", calendar: calendar)
            == ListChange(kind: .added, count: 2, at: now.addingTimeInterval(-60)))
    }

    @Test func aTickNewerThanAnyAddWins() {
        let watch = list(.watch, [item("L", -3_600, done: -30, by: "M"), item("M", -600)])
        #expect(watch.latestChange(by: "M", calendar: calendar)?.kind == .done)
    }

    @Test func noChangeFromThePartner() {
        #expect(list(.travel, [item("L", -60)]).latestChange(by: "M") == nil)
    }

    @Test func thePartnersNewestChangeGoesFirst() {
        let groceries = list(.groceries, [item("M", -3_600)])
        let watch = list(.watch, [item("M", -60)])
        let travel = list(.travel)
        let books = list(.books)
        let layout = UsListsLayout(lists: [books, watch, travel, groceries], partner: "M")
        #expect(layout.cards.map(\.kind) == [.watch, .groceries, .travel])
        #expect(layout.rows.map(\.id) == [books.id])
    }

    @Test func aSecondListOfAKindIsARow() {
        let first = list(.groceries), second = list(.groceries)
        let layout = UsListsLayout(lists: [first, second], partner: "M")
        #expect(layout.cards.map(\.id) == [first.id])
        #expect(layout.rows.map(\.id) == [second.id])
    }

    @Test func untouchedCardsKeepGroceriesWatchPlaces() {
        let layout = UsListsLayout(lists: [list(.travel), list(.watch), list(.groceries)], partner: "M")
        #expect(layout.cards.map(\.kind) == [.groceries, .watch, .travel])
    }
}
