import Foundation
import Testing

@testable import Pet

@MainActor
@Suite struct GiftTests {
  private let catalog = ShopCatalog.standard
  private func store() -> ShopStore { ShopStore(storage: .memory()) }
  private func item(_ id: String) throws -> ShopItem { try #require(catalog.item(id)) }

  @Test func aGivenItemLeavesTheClosetAndAReceivedOneArrives() throws {
    let shop = store()
    let fish = try item("treat-fish")
    try shop.buy(fish, transaction: "b1")
    #expect(shop.owned(fish) == 1)
    try shop.give(fish, transaction: "g1")
    #expect(shop.owned(fish) == 0)
    try shop.receive(fish, transaction: "r1")
    #expect(shop.owned(fish) == 1)
  }

  @Test func receivingCostsNothing() throws {
    let shop = store()
    let before = shop.stamps
    try shop.receive(try item("furniture-yarn"), transaction: "r1")
    #expect(shop.stamps == before)
  }

  @Test func givingWhatIsNotThereIsRefused() throws {
    let shop = store()
    #expect(throws: ShopError.notInCloset) {
      try shop.give(try item("treat-fish"), transaction: "g1")
    }
  }

  @Test func aMaterialCannotBeWrapped() throws {
    let shop = store()
    let material = try #require(catalog.items(in: .materials).first)
    #expect(throws: ShopError.wrongKind) { try shop.give(material, transaction: "g1") }
    #expect(throws: ShopError.wrongKind) { try shop.receive(material, transaction: "r1") }
  }

  @Test func theSameTransactionAppliesOnce() throws {
    let shop = store()
    let fish = try item("treat-fish")
    #expect(try shop.receive(fish, transaction: "r1") == .applied)
    #expect(try shop.receive(fish, transaction: "r1") == .duplicate)
    #expect(shop.owned(fish) == 1)
    try shop.buy(fish, transaction: "b1")
    #expect(try shop.give(fish, transaction: "g1") == .applied)
    #expect(try shop.give(fish, transaction: "g1") == .duplicate)
    #expect(shop.owned(fish) == 1)
  }
}
