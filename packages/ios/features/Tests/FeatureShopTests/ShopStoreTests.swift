import Foundation
import ShopInterface
import Synchronization
import Testing
import Transport
import Wire

@testable import FeatureShop

/// A server for one test: what it answers, and every request it was sent.
private final class FakeRoom: Sendable {
  let shop: Mutex<ShopResponse>
  let orders = Mutex<[OrderRequest]>([])
  /// Orders that fail with `.network` before one gets through.
  let drops = Mutex(0)

  init(_ shop: ShopResponse) { self.shop = Mutex(shop) }

  var client: ShopClient {
    ShopClient(
      fetch: { () async throws(TransportError) in self.shop.withLock { $0 } },
      order: { (request) async throws(TransportError) in
        self.orders.withLock { $0.append(request) }
        let dropped = self.drops.withLock { drops in
          guard drops > 0 else { return false }
          drops -= 1
          return true
        }
        if dropped { throw .network("lost") }
        let shop = self.shop.withLock { $0 }
        return OrderResponse(
          entry: CoinEntry(
            id: "spend:\(request.id.rawValue)", kind: .spend, amount: -140, ref: "x", at: 0),
          shop: shop)
      },
      wish: { (_) async throws(TransportError) in self.shop.withLock { $0 } })
  }
}

private func room(_ balance: Int, items: [String] = []) -> ShopResponse {
  ShopResponse(balance: balance, inks: [.free], items: items.map(RoomItemId.init), wishlist: [])
}

@MainActor
@Suite struct ShopStoreTests {
  /// A wallet file and a cat, as the app would give the store.
  final class Side {
    var mirrors: [ShopMachine.Mirror] = []
    var fed = 0
    var noticed = 0
    var left = 0
  }

  private func store(_ server: FakeRoom, side: Side) -> ShopStore {
    .shop(
      ShopServices(
        client: { server.client }, undoWindow: { .zero }, retryDelay: { .zero },
        mirror: { side.mirrors.append($0) }, mirrorBalance: { _ in }, mirrorWish: { _, _ in },
        markGifted: { _ in }, leaveWallet: { side.left += 1 }, catFed: { side.fed += 1 },
        catNoticed: { side.noticed += 1 }))
  }

  @Test func aLostOrderIsAskedAgainUnderTheSameId() async {
    let server = FakeRoom(room(400))
    server.drops.withLock { $0 = 2 }
    let side = Side()
    let store = store(server, side: side)
    store.send(.connected(last: ShopMachine.Mirror(balance: 0, owned: [], wishlist: [])))
    await store.settled()

    let lamp = ShopOrder(
      offer: .item(RoomItemId("lamp")), itemIDs: ["lamp"], cost: 140, title: "Lamp")
    let id = UUID()
    store.send(.buyTapped(lamp, id: id, at: .now))
    server.shop.withLock { $0 = room(260, items: ["lamp"]) }
    await store.settled()

    let orders = server.orders.withLock { $0 }
    #expect(orders.count == 3)
    #expect(Set(orders.map(\.id)) == [IdempotencyKey(id.uuidString)])
    guard case .open(let shop) = store.state else {
      Issue.record("not open")
      return
    }
    #expect(shop.pending.isEmpty)
    #expect(shop.coins == 260)
    #expect(shop.owned.contains("lamp"))
    #expect(side.noticed == 1)
    #expect(side.mirrors.last?.balance == 260)
  }

  @Test func anOrderLostOnEveryTryIsTakenBack() async {
    let server = FakeRoom(room(400))
    server.drops.withLock { $0 = 10 }
    let side = Side()
    let store = store(server, side: side)
    store.send(.connected(last: ShopMachine.Mirror(balance: 0, owned: [], wishlist: [])))
    await store.settled()

    store.send(.treatTapped(id: UUID(), at: .now))
    await store.settled()
    #expect(server.orders.withLock { $0.count } == 3)
    #expect(side.fed == 1)
    guard case .open(let shop) = store.state else {
      Issue.record("not open")
      return
    }
    #expect(shop.coins == 400)
    #expect(shop.pending.isEmpty)

    store.send(.disconnected)
    await store.settled()
    #expect(side.left == 1)
  }
}
