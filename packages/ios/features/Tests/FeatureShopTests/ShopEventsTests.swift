import Foundation
import Persistence
import ProfileInterface
import ShopInterface
import Testing
import Transport
import Wire

@testable import FeatureShop

private final class Care: CatTending {
  func fed() {}
  func notice() {}
}

private nonisolated func room(_ balance: Int, giftDay: String? = nil) -> ShopResponse {
  ShopResponse(
    balance: balance, inks: [.free], items: [RoomItemId("lamp")], wishlist: [], giftDay: giftDay,
    bonuses: [])
}

@MainActor
@Suite(.serialized) struct ShopEventsTests {
  private let walletFile = "Tests/\(UUID().uuidString)-wallet.json"
  private let heard = Heard()

  /// The model's order tasks outlive a test and read it unowned, so no model is freed before the run ends.
  private static var kept: [ShopModel] = []

  @MainActor final class Heard {
    var events: [ClientEvent] = []
  }

  private func shop() -> ShopModel {
    let heard = heard
    let model = ShopModel(
      wallet: WalletStore(file: walletFile),
      couple: CoupleStore(
        load: { nil }, save: { _ in }, photoURL: { URL(fileURLWithPath: "/tmp/\($0)") }),
      care: Care(), events: EventReporter { heard.events.append($0) }, catName: { "Mochi" })
    model.undoWindow = .seconds(60)
    model.retryDelay = .zero
    Self.kept.append(model)
    return model
  }

  private func client(
    gift: @escaping @Sendable (OpenGiftRequest) async throws(TransportError) -> OpenGiftResponse = {
      (_) async throws(TransportError) in throw .network("unused")
    }
  ) -> ShopClient {
    ShopClient(
      fetch: { () async throws(TransportError) in room(2000) },
      order: { (_) async throws(TransportError) in throw .network("held") },
      wish: { (_) async throws(TransportError) in room(2000) },
      openGift: gift)
  }

  private func cleanUp() {
    SharedFile.flush()
    try? FileManager.default.removeItem(at: SharedFile.url(walletFile))
  }

  @Test func openingAndLookingAreCounted() throws {
    defer { cleanUp() }
    let model = shop()
    model.opened()
    model.viewed(try #require(Catalog.item("yarn", cat: "Mochi")))
    model.offerViewed("cosy-corner")
    #expect(
      heard.events == [
        ClientEvent(.shopOpened), ClientEvent(.shopItemViewed, detail: "yarn"),
        ClientEvent(.shopOfferViewed, detail: "cosy-corner"),
      ])
  }

  @Test func aBuyIsCountedWithItsPriceAndAnUndoGivesItBack() async throws {
    defer { cleanUp() }
    let model = shop()
    await model.connect(client())
    let yarn = try #require(Catalog.item("yarn", cat: "Mochi"))
    let price = model.price(of: yarn)

    #expect(model.buy(yarn))
    #expect(heard.events == [ClientEvent(.shopItemBought, detail: "yarn", value: price)])
    #expect(model.undo(try #require(model.lastPurchase)))
    #expect(heard.events.last == ClientEvent(.shopPurchaseUndone, detail: "yarn", value: price))
  }

  @Test func aBundleIsCountedAsOne() async throws {
    defer { cleanUp() }
    let model = shop()
    await model.connect(client())
    let bundle = try #require(model.offers.bundles.first)
    let price = try #require(model.offers.price(of: bundle, owned: model.owned)).price

    #expect(model.buy(bundle))
    #expect(heard.events == [ClientEvent(.shopBundleBought, detail: bundle.id, value: price)])
  }

  @Test func aBuyTheCoinsDoNotCoverIsNotCounted() async throws {
    defer { cleanUp() }
    let model = shop()
    await model.connect(
      ShopClient(
        fetch: { () async throws(TransportError) in room(0) },
        order: { (_) async throws(TransportError) in throw .network("held") },
        wish: { (_) async throws(TransportError) in room(0) }))
    #expect(!model.buy(try #require(Catalog.item("yarn", cat: "Mochi"))))
    #expect(heard.events.isEmpty)
  }

  @Test func theDailyGiftIsCountedWithItsCoins() async throws {
    defer { cleanUp() }
    let model = shop()
    let today = ShopModel.localDay(.now)
    await model.connect(
      client(gift: { (_) async throws(TransportError) in
        OpenGiftResponse(
          entry: CoinEntry(id: "gift:\(today)", kind: .gift, amount: 30, ref: today, at: 0),
          reward: .coins(30), shop: room(2030, giftDay: today))
      }))

    #expect(await model.openGift() == .opened(.coins(30)))
    #expect(heard.events == [ClientEvent(.shopDailyGiftClaimed, detail: "coins", value: 30)])
  }

  @Test func everyCountedEventKeepsItsRule() async throws {
    defer { cleanUp() }
    let model = shop()
    await model.connect(client())
    model.opened()
    for item in Catalog.items(in: .furniture, cat: "Mochi").prefix(5) {
      model.viewed(item)
      _ = model.buy(item)
    }
    #expect(!heard.events.isEmpty)
    #expect(heard.events.allSatisfy { $0.problem == nil })
  }
}
