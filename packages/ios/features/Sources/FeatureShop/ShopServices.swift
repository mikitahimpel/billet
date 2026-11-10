import BilletKit
import Foundation
import ShopInterface
import Transport
import Wire

public typealias ShopStore = Store<ShopMachine>

/// What the shop's outputs run on. The closures on the main actor touch the wallet file and the
/// cat, which the app owns.
public struct ShopServices: Sendable {
  /// The pair's room on the server; nil while this phone follows none.
  public var client: @MainActor @Sendable () -> ShopClient?
  public var undoWindow: @MainActor @Sendable () -> Duration
  /// Between tries of one request while the network is down.
  public var retryDelay: @MainActor @Sendable () -> Duration
  /// Tries of one request while the network is down, the first included.
  public var attempts: Int
  public var utcOffset: @Sendable (Date) -> Int
  public var mirror: @MainActor @Sendable (ShopMachine.Mirror) -> Void
  public var mirrorBalance: @MainActor @Sendable (Int) -> Void
  public var mirrorWish: @MainActor @Sendable (_ itemID: String, _ wished: Bool) -> Void
  public var markGifted: @MainActor @Sendable ([String]) -> Void
  public var leaveWallet: @MainActor @Sendable () -> Void
  public var catFed: @MainActor @Sendable () -> Void
  public var catNoticed: @MainActor @Sendable () -> Void

  public init(
    client: @escaping @MainActor @Sendable () -> ShopClient?,
    undoWindow: @escaping @MainActor @Sendable () -> Duration,
    retryDelay: @escaping @MainActor @Sendable () -> Duration,
    attempts: Int = 3,
    utcOffset: @escaping @Sendable (Date) -> Int = ShopMachine.utcOffset,
    mirror: @escaping @MainActor @Sendable (ShopMachine.Mirror) -> Void,
    mirrorBalance: @escaping @MainActor @Sendable (Int) -> Void,
    mirrorWish: @escaping @MainActor @Sendable (_ itemID: String, _ wished: Bool) -> Void,
    markGifted: @escaping @MainActor @Sendable ([String]) -> Void,
    leaveWallet: @escaping @MainActor @Sendable () -> Void,
    catFed: @escaping @MainActor @Sendable () -> Void,
    catNoticed: @escaping @MainActor @Sendable () -> Void
  ) {
    self.client = client
    self.undoWindow = undoWindow
    self.retryDelay = retryDelay
    self.attempts = attempts
    self.utcOffset = utcOffset
    self.mirror = mirror
    self.mirrorBalance = mirrorBalance
    self.mirrorWish = mirrorWish
    self.markGifted = markGifted
    self.leaveWallet = leaveWallet
    self.catFed = catFed
    self.catNoticed = catNoticed
  }

  /// The server's page of wallet entries.
  static let coinsPage = 100

  /// Runs one output and returns the event it comes to, if any.
  public func run(_ output: ShopMachine.Output) async -> ShopMachine.Event? {
    switch output {
    case .fetch(let request):
      guard let client = await client() else { return .fetchFailed(request: request) }
      do {
        return .fetched(try await client.fetch(), request: request)
      } catch {
        return .fetchFailed(request: request)
      }
    case .loadInks:
      guard let client = await client() else { return .inksFailed }
      do {
        return .inksLoaded(try await client.inks().inks)
      } catch {
        return .inksFailed
      }
    case .wait(let id):
      try? await Task.sleep(for: await undoWindow())
      return .undoWindowPassed(id)
    case .order(let purchase):
      guard let client = await client() else { return .orderFailed(purchase.id, .unavailable) }
      let request = OrderRequest(
        id: purchase.key, offer: purchase.offer, utcOffsetSeconds: utcOffset(purchase.date))
      do {
        let response = try await retrying { () async throws(TransportError) in
          try await client.order(request)
        }
        return .ordered(purchase.id, response.shop)
      } catch {
        return .orderFailed(purchase.id, ShopError(error))
      }
    case .wish(let itemID, let wished):
      guard let client = await client() else { return .wishFailed }
      let request = WishRequest(item: RoomItemId(itemID), wished: wished)
      do {
        return .wished(try await client.wish(request))
      } catch {
        return .wishFailed
      }
    case .openGift:
      guard let client = await client() else { return .giftFailed(.unavailable) }
      let request = OpenGiftRequest(utcOffsetSeconds: utcOffset(Date()))
      do {
        let response = try await retrying { () async throws(TransportError) in
          try await client.openGift(request)
        }
        return .giftOpened(ShopInterface.GiftReward(response.reward), response.shop)
      } catch {
        return .giftFailed(ShopError(error))
      }
    case .claimBonus(let collection):
      guard let client = await client() else { return .bonusFailed(.unavailable) }
      let request = ClaimBonusRequest(collection: collection)
      do {
        let response = try await retrying { () async throws(TransportError) in
          try await client.claimBonus(request)
        }
        return .bonusClaimed(response.shop)
      } catch {
        return .bonusFailed(ShopError(error))
      }
    case .earn(let event):
      guard let client = await client() else { return nil }
      let request = EarnRequest(event: event, utcOffsetSeconds: utcOffset(Date()))
      do {
        let response = try await retrying { () async throws(TransportError) in
          try await client.earn(request)
        }
        return .earned(balance: response.balance)
      } catch {
        return nil
      }
    case .loadHistory(let limit):
      guard let client = await client() else { return .historyFailed }
      return await history(limit: limit, client: client)
    case .mirror(let mirror):
      await self.mirror(mirror)
      return nil
    case .mirrorBalance(let balance):
      await mirrorBalance(balance)
      return nil
    case .mirrorWish(let itemID, let wished):
      await mirrorWish(itemID, wished)
      return nil
    case .markGifted(let items):
      await markGifted(items)
      return nil
    case .leaveWallet:
      await leaveWallet()
      return nil
    case .catFed:
      await catFed()
      return nil
    case .catNoticed:
      await catNoticed()
      return nil
    }
  }

  /// Reads the latest wallet entries, paging from the oldest as the server lists them.
  private func history(limit: Int, client: ShopClient) async -> ShopMachine.Event {
    var after: String?
    var latest: [CoinEntry] = []
    while true {
      guard let page = try? await client.coins(after) else { return .historyFailed }
      latest = Array((latest + page.entries).suffix(limit))
      guard page.entries.count >= Self.coinsPage, let last = page.entries.last else {
        return .historyLoaded(latest.reversed(), balance: page.balance)
      }
      after = last.id
    }
  }

  /// Asks again while the network is down, with the same request.
  private func retrying<T>(
    _ call: () async throws(TransportError) -> T
  ) async throws(TransportError) -> T {
    var attempt = 1
    while true {
      do {
        return try await call()
      } catch {
        guard case .network = error, attempt < attempts else { throw error }
        attempt += 1
        try? await Task.sleep(for: await retryDelay())
      }
    }
  }
}

extension ShopStore {
  public static func shop(_ services: ShopServices) -> ShopStore {
    ShopStore(initial: .initial) { output in await services.run(output) }
  }
}

extension ShopError {
  public init(_ error: TransportError) {
    switch error {
    case .api(.notEnoughCoins(let needed, let have)):
      self = .notEnoughCoins(needed: needed, have: have)
    case .api(.alreadyOwned): self = .alreadyOwned
    case .api(.giftTaken(let day)): self = .giftTaken(day: day)
    case .api(.bonusTaken): self = .bonusTaken
    case .api(.collectionIncomplete): self = .collectionIncomplete
    case .api(.unauthorized): self = .signedOut
    case .api(.invalidRequest), .api(.unavailable), .api(.notFound), .api(.invalidInvite),
      .api(.alreadyPaired), .api(.appleIdInUse), .api(.invalidPurchase), .api(.inkNotOwned),
      .api(.catNotAdopted), .api(.priceChanged), .api(.layoutRefused), .api(.streakNotRestorable),
      .network, .status,
      .maintenance, .encoding, .decoding:
      self = .unavailable
    }
  }
}
