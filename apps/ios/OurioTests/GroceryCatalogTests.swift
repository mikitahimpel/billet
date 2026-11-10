import Foundation
import MomentsInterface
import OurioShared
import Testing
import UsInterface
@testable import Billet

@Suite struct GroceryCatalogTests {
    private let catalog = GroceryCatalog.bundled

    @Test(arguments: [
        ("Lemons", GroceryAisle.produce),
        ("лимоны", .produce),
        ("Овсяное молоко", .dairy),
        ("oat milk", .dairy),
        ("Tomatoes", .produce),
        ("ЯЙЦА", .dairy),
        ("Ёжики из курицы", .meat),
        ("hand cream", .household),
        ("ice cream", .frozen),
    ])
    func namesMatchTheirAisle(name: String, aisle: GroceryAisle) {
        #expect(catalog.aisle(for: name) == aisle)
    }

    @Test func theLongestNameWins() throws {
        #expect(try #require(catalog.entry(for: "organic oat milk")).words.en.contains("oat milk"))
        #expect(try #require(catalog.entry(for: "овсяное молоко")).words.ru.contains("овсяное молоко"))
    }

    @Test func anUnknownNameGoesToOther() {
        #expect(catalog.entry(for: "Flux capacitor") == nil)
        #expect(catalog.aisle(for: "Flux capacitor") == .other)
    }

    @Test func theCatalogIsWhole() {
        #expect(catalog.entries.count >= 280)
    }

    @Test func suggestionsFollowWhatIsTyped() {
        let milk = catalog.suggestions(for: "mil", limit: 4).map(\.text)
        #expect(milk.first == "Milk")
        #expect(milk.contains("Milkshake"))
        #expect(catalog.suggestions(for: "мол", limit: 4).first?.text == "Молоко")
        #expect(catalog.suggestions(for: "  ", limit: 4).isEmpty)
    }

    @Test func thePairsAisleIsRememberedForTheNextOne() {
        var history = GroceryHistory()
        let first = ListItem(text: "Lemons", author: "L", aisle: "drinks")
        history.observe([UsList(kind: .groceries, title: "Groceries", icon: ListKind.groceries.icon, items: [first])])

        #expect(catalog.aisle(for: ListItem(text: "lemon", author: "M"), history: history) == .drinks)
        #expect(catalog.suggestions(for: "lem", history: history, limit: 4).first?.aisle == .drinks)
    }

    @Test func oftenBoughtCountsEachItemOnce() {
        var history = GroceryHistory()
        let list = { (items: [ListItem]) in
            [UsList(kind: .groceries, title: "Groceries", icon: ListKind.groceries.icon, items: items)]
        }
        let milk = ListItem(text: "Milk", author: "L")
        history.observe(list([milk]))
        history.observe(list([milk]))
        history.observe(list([]))
        history.observe(list([ListItem(text: "milk", author: "M"), ListItem(text: "Bread", author: "M")]))

        #expect(history.often(limit: 8).map(\.count) == [2, 1])
        #expect(history.often(limit: 8).first?.text == "milk")
    }

    @Test func aQuantityLeadsTheNote() {
        #expect(GroceryItemSheet.split("2, for tea") == ("2", "for tea"))
        #expect(GroceryItemSheet.split("500 g") == ("500 g", nil))
        #expect(GroceryItemSheet.split("the ripe ones") == (nil, "the ripe ones"))
        #expect(GroceryItemSheet.split("  ") == (nil, nil))
        #expect(GroceryItemSheet.amount("2", "for tea") == "2, for tea")
    }
}
