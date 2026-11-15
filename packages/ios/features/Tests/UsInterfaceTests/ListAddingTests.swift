import Foundation
import Persistence
import Testing
@testable import UsInterface

/// Every list kind takes an item from where it opens: a typed line into the list's own field, a title or a country
/// from its search, a wish from its editor. What the list holds afterwards is what these tests read.
@Suite struct ListAddingTests {
  private let path = "Tests/\(UUID().uuidString)-us.json"

  private func store() -> UsStore { UsStore(file: path) }

  private func cleanUp() {
    SharedFile.flush()
    try? FileManager.default.removeItem(at: SharedFile.url(path))
  }

  private func list(_ kind: ListKind, in us: UsStore) throws -> UUID {
    try #require(us.lists.first { $0.kind == kind }).id
  }

  @Test func aTypedLineIsTrimmedAndLandsOnTheList() throws {
    defer { cleanUp() }
    let us = store()
    let groceries = try list(.groceries, in: us)
    #expect(us.addTyped("  Oat milk \n", to: groceries, author: "L"))
    #expect(us.list(groceries)?.items.map(\.text) == ["Oat milk"])
    #expect(us.list(groceries)?.items.first?.author == "L")
  }

  @Test(arguments: ["", "   ", "\n"])
  func aBlankLineAddsNothing(_ line: String) throws {
    defer { cleanUp() }
    let us = store()
    let groceries = try list(.groceries, in: us)
    #expect(!us.addTyped(line, to: groceries, author: "L"))
    #expect(us.list(groceries)?.items.isEmpty == true)
  }

  @Test func aGroceryGoesToTheAisleThePairLastGaveIt() throws {
    defer { cleanUp() }
    let us = store()
    let groceries = try list(.groceries, in: us)
    us.addTyped("Oat milk", to: groceries, author: "L")
    let first = try #require(us.list(groceries)?.items.first)
    #expect(first.aisle == nil)
    var details = first.details
    details.aisle = "dairy"
    us.editItem(first.id, in: groceries, details: details)
    us.clearDone(in: groceries)
    us.deleteItem(first.id, in: groceries)

    us.addTyped("oat milk", to: groceries, author: "M")
    #expect(us.list(groceries)?.items.first?.aisle == "dairy")
  }

  @Test func otherListsKeepNoAisle() throws {
    defer { cleanUp() }
    let us = store()
    let watch = try list(.watch, in: us)
    us.addTyped("Home movie", to: watch, author: "L")
    #expect(us.list(watch)?.items.first?.aisle == nil)
  }

  @Test func aTitleSearchCannotFindIsAddedAsText() throws {
    defer { cleanUp() }
    let us = store()
    let watch = try list(.watch, in: us)
    us.addItem("Home movie", to: watch, author: "L")
    let item = try #require(us.list(watch)?.items.first)
    #expect(item.text == "Home movie")
    #expect(item.details.media == nil)
  }

  @Test func aCountryIsAddedOnceAndItsPlaceGoesUnderIt() throws {
    defer { cleanUp() }
    let us = store()
    let travel = try list(.travel, in: us)
    us.addTravel(country: "PT", to: travel, author: "L")
    us.addTravel(country: "PT", place: "Lisbon", to: travel, author: "L")
    let items = try #require(us.list(travel)?.items)
    #expect(items.filter { $0.isCountry && $0.country == "PT" }.count == 1)
    #expect(items.contains { $0.text == "Lisbon" && $0.country == "PT" && !$0.isCountry })
  }

  @Test func aNewListStartsEmptyAndTakesItsFirstItem() throws {
    defer { cleanUp() }
    let us = store()
    let created = us.addList(kind: .custom, title: "Packing", icon: ListKind.custom.icon)
    #expect(us.list(created.id)?.title == "Packing")
    #expect(us.list(created.id)?.items.isEmpty == true)
    us.addTyped("Passport", to: created.id, author: "L")
    #expect(us.list(created.id)?.items.map(\.text) == ["Passport"])
  }

  @Test func aWishJoinsItsOwnersWishlist() {
    defer { cleanUp() }
    let us = store()
    us.upsertWish(WishItem(owner: "L", title: "Linen scarf"))
    #expect(us.wishes(of: "L").map(\.title) == ["Linen scarf"])
    #expect(us.wishes(of: "M").isEmpty)
  }
}
