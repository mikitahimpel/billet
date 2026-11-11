import BilletKit
import Foundation
import ShopInterface
import Wire

/// Only the server changes coins; the balance is its last answer less buys not yet sent. A buy
/// shows at once, waits out its Undo window, then is ordered under one id for every retry. One
/// refused or never delivered is taken back and the room read again.
public enum ShopMachine: Machine {
  public static let treatPrice = 10

  /// What this phone last heard from the server: the wallet file keeps it between launches.
  public struct Mirror: Equatable, Sendable {
    public var balance: Int
    /// Items and inks, as the wallet file keeps them together.
    public var owned: Set<String>
    public var wishlist: Set<String>
    /// Where the pair stood its pieces; nil from a server before placements.
    public var layout: [RoomPlacement]?

    public init(
      balance: Int, owned: Set<String>, wishlist: Set<String>, layout: [RoomPlacement]? = nil
    ) {
      self.balance = balance
      self.owned = owned
      self.wishlist = wishlist
      self.layout = layout
    }

    public init(_ shop: ShopResponse) {
      balance = shop.balance
      owned = Set(shop.items.map(\.rawValue)).union(shop.inks.map(\.rawValue))
      wishlist = Set(shop.wishlist.map(\.rawValue))
      layout = shop.layout
    }
  }

  /// What the purchase moment shows: the latest buy, or the latest one the server didn't take.
  public enum Moment: Equatable, Sendable {
    case placed(Purchase)
    case refused(Purchase)
  }

  /// A read of the room; a result for another request changes nothing.
  public enum Fetch: Equatable, Sendable {
    case idle
    case reading(request: Int)
  }

  public enum InkLoad: Equatable, Sendable {
    case idle
    case loading
  }

  /// The day's gift, from the tap to the outcome the card shows.
  public enum Gift: Equatable, Sendable {
    case idle
    case opening(day: String)
    /// Refused: the room is read again, and shows whether the gift is open for `day`.
    case checking(day: String, request: Int)
    case opened(ShopInterface.GiftReward)
    case taken
    case failed
  }

  /// A collection's bonus, from the tap to the answer the card shows.
  public enum Bonus: Equatable, Sendable {
    case idle
    case claiming(collection: String)
    /// Refused: the room is read again before the card decides.
    case refusing(collection: String, request: Int)
    case claimed(collection: String)
    case refused(collection: String)
  }

  public enum HistoryLoad: Equatable, Sendable {
    case idle
    case loading(limit: Int)
  }

  public struct PairShop: Equatable, Sendable {
    public var mirror: Mirror
    /// The pair's local day it last opened the gift on, as the server said.
    public var giftDay: String?
    /// The collections whose bonus the pair has collected.
    public var bonuses: Set<String> = []
    /// The inks on sale once the server answered; empty until then.
    public var inks: [Ink] = []
    /// The pair's latest wallet entries, newest first.
    public var history: [CoinEntry] = []
    /// Buys shown on this phone that the server hasn't charged yet.
    public var pending: [Purchase] = []
    public var moment: Moment?
    /// The Coins sheet, open when set.
    public var ask: CoinsAsk?
    /// The Coins sheet for a buy the partner outspent: it opens once the room is read again, on
    /// the balance the server has now.
    public var askAfterRead: CoinsAsk?
    public var fetch = Fetch.idle
    public var inkLoad = InkLoad.idle
    public var gift = Gift.idle
    public var bonus = Bonus.idle
    public var historyLoad = HistoryLoad.idle
    /// Reads asked so far; the next one is this plus one.
    public var requests = 0

    public init(mirror: Mirror, ask: CoinsAsk? = nil) {
      self.mirror = mirror
      self.ask = ask
    }

    public var coins: Int { max(0, mirror.balance - pending.reduce(0) { $0 + $1.cost }) }
    public var owned: Set<String> { mirror.owned.union(pending.flatMap(\.added)) }
    public var wishlist: Set<String> { mirror.wishlist.subtracting(pending.flatMap(\.added)) }
    /// Pieces bought as gifts that the server hasn't charged yet.
    public var giftedPending: Set<String> { Set(pending.filter(\.asGift).flatMap(\.added)) }

    mutating func apply(_ shop: ShopResponse) {
      mirror = Mirror(shop)
      giftDay = shop.giftDay
      bonuses = Set(shop.bonuses)
    }

    /// Starts a read of the room; a read already in flight is forgotten.
    mutating func read() -> Int {
      requests += 1
      fetch = .reading(request: requests)
      return requests
    }
  }

  public enum State: Equatable, Sendable {
    /// No pair's room on the server: nothing can be bought or earned. A buy is refused out loud.
    case offline(refused: Purchase?, ask: CoinsAsk?)
    case open(PairShop)

    public static let initial = State.offline(refused: nil, ask: nil)
  }

  public enum Event: Equatable, Sendable {
    /// This phone follows a pair's room; `last` is what the wallet file holds meanwhile.
    case connected(last: Mirror)
    case disconnected
    /// Back in the foreground, or after a refusal: the inks and the room are read again.
    case refreshAsked
    /// The room's shop as the socket pushes it, after either partner's change.
    case pushed(ShopResponse)
    case buyTapped(ShopOrder, id: UUID, at: Date)
    case treatTapped(id: UUID, at: Date)
    case undoTapped(Purchase.ID)
    case wishToggled(itemID: String, wished: Bool)
    /// `day` is this phone's local day, the one the server counts the gift on.
    case giftTapped(day: String)
    case giftShown
    /// `itemIDs` are the collection's pieces; the bonus waits until every one is owned.
    case bonusTapped(collection: String, itemIDs: [String])
    case bonusShown
    case coinsAsked(CoinsAsk)
    case coinsSheetClosed
    case earnAsked(EarnEvent)
    case historyAsked(limit: Int)

    case fetched(ShopResponse, request: Int)
    case fetchFailed(request: Int)
    case inksLoaded([Ink])
    case inksFailed
    case undoWindowPassed(Purchase.ID)
    case ordered(Purchase.ID, ShopResponse)
    case orderFailed(Purchase.ID, ShopError)
    case wished(ShopResponse)
    case wishFailed
    case giftOpened(ShopInterface.GiftReward, ShopResponse)
    case giftFailed(ShopError)
    case bonusClaimed(ShopResponse)
    case bonusFailed(ShopError)
    case earned(balance: Int)
    case historyLoaded([CoinEntry], balance: Int)
    case historyFailed
  }

  public enum Output: Equatable, Sendable {
    case fetch(request: Int)
    case loadInks
    /// The Undo window; comes back as `.undoWindowPassed`.
    case wait(Purchase.ID)
    /// Asked again while the network is down, under the same id; one result either way.
    case order(Purchase)
    case wish(itemID: String, wished: Bool)
    case openGift
    case claimBonus(collection: String)
    case earn(EarnEvent)
    case loadHistory(limit: Int)
    /// The wallet file takes the server's answer, for the widgets and for offline.
    case mirror(Mirror)
    case mirrorBalance(Int)
    case mirrorWish(itemID: String, wished: Bool)
    case markGifted([String])
    /// The pair ended: what the wallet had was the room's.
    case leaveWallet
    case catFed
    case catNoticed
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch state {
    case .offline(let refused, let ask): offline(refused: refused, ask: ask, event)
    case .open(let shop): open(shop, event)
    }
  }

  private static func offline(refused: Purchase?, ask: CoinsAsk?, _ event: Event) -> (
    State, [Output]
  ) {
    let state = State.offline(refused: refused, ask: ask)
    switch event {
    case .connected(let last):
      var shop = PairShop(mirror: last, ask: ask)
      let request = shop.read()
      shop.inkLoad = .loading
      return (.open(shop), [.loadInks, .fetch(request: request)])
    case .buyTapped(let order, let id, let at):
      // Without a room to buy in, the tap says so rather than doing nothing.
      let purchase = Purchase(order, id: id, added: order.itemIDs, at: at, stage: .undoable)
      return (.offline(refused: purchase, ask: ask), [])
    case .wishToggled(let itemID, let wished):
      return (state, [.mirrorWish(itemID: itemID, wished: wished)])
    case .coinsAsked(let ask):
      return (.offline(refused: refused, ask: ask), [])
    case .coinsSheetClosed:
      return (.offline(refused: refused, ask: nil), [])
    case .disconnected, .refreshAsked, .pushed, .treatTapped, .undoTapped, .giftTapped, .giftShown,
      .bonusTapped, .bonusShown, .earnAsked, .historyAsked, .fetched, .fetchFailed, .inksLoaded,
      .inksFailed, .undoWindowPassed, .ordered, .orderFailed, .wished, .wishFailed, .giftOpened,
      .giftFailed, .bonusClaimed, .bonusFailed, .earned, .historyLoaded, .historyFailed:
      return (state, [])
    }
  }

  private static func open(_ shop: PairShop, _ event: Event) -> (State, [Output]) {
    var shop = shop
    let state = State.open(shop)
    switch event {
    case .connected(let last):
      // A room followed anew: the buys in flight were the old one's.
      var fresh = PairShop(mirror: last, ask: shop.ask)
      let request = fresh.read()
      fresh.inkLoad = .loading
      return (.open(fresh), [.loadInks, .fetch(request: request)])
    case .disconnected:
      return (.offline(refused: nil, ask: shop.ask), [.leaveWallet])
    case .refreshAsked:
      let request = shop.read()
      shop.inkLoad = .loading
      return (.open(shop), [.loadInks, .fetch(request: request)])
    case .pushed(let response):
      shop.apply(response)
      return (.open(shop), [.mirror(shop.mirror)])

    case .buyTapped(let order, let id, let at):
      let added = order.itemIDs.filter { !shop.owned.contains($0) }
      guard !added.isEmpty else { return (state, []) }
      guard shop.coins >= order.cost else {
        shop.ask = CoinsAsk(missing: order.cost - shop.coins, retry: order)
        return (.open(shop), [])
      }
      // Room pieces wait out their Undo window before the order; an ink has no Undo and goes at once.
      let stage: Purchase.Stage = order.kind == .item ? .undoable : .ordering
      let purchase = Purchase(order, id: id, added: added, at: at, stage: stage)
      shop.pending.append(purchase)
      shop.moment = .placed(purchase)
      let next: Output = stage == .undoable ? .wait(id) : .order(purchase)
      return (.open(shop), [next, .catNoticed])
    case .treatTapped(let id, let at):
      let order = ShopOrder.treat(price: treatPrice)
      guard shop.coins >= treatPrice else {
        shop.ask = CoinsAsk(missing: treatPrice - shop.coins, retry: order)
        return (.open(shop), [])
      }
      // Mochi eats it at once and the server is asked at once, as it has no Undo.
      let treat = Purchase(order, id: id, added: [], at: at, stage: .ordering)
      shop.pending.append(treat)
      return (.open(shop), [.order(treat), .catFed])
    case .undoTapped(let id):
      guard let index = shop.pending.firstIndex(where: { $0.id == id }),
        shop.pending[index].stage == .undoable
      else { return (state, []) }
      shop.pending.remove(at: index)
      if case .placed(let placed) = shop.moment, placed.id == id { shop.moment = nil }
      return (.open(shop), [])
    case .undoWindowPassed(let id):
      guard let index = shop.pending.firstIndex(where: { $0.id == id }),
        shop.pending[index].stage == .undoable
      else { return (state, []) }
      shop.pending[index].stage = .ordering
      return (.open(shop), [.order(shop.pending[index])])
    case .ordered(let id, let response):
      guard let purchase = shop.pending.first(where: { $0.id == id }) else { return (state, []) }
      shop.pending.removeAll { $0.id == id }
      shop.apply(response)
      let gifted: [Output] = purchase.asGift ? [.markGifted(purchase.added)] : []
      return (.open(shop), gifted + [.mirror(shop.mirror)])
    case .orderFailed(let id, let error):
      guard let purchase = shop.pending.first(where: { $0.id == id }) else { return (state, []) }
      shop.pending.removeAll { $0.id == id }
      if case .placed(let placed) = shop.moment, placed.id == id { shop.moment = nil }
      switch error {
      case .notEnoughCoins(let needed, let have):
        // The partner spent the coins first: offer to top up and finish, rather than only refusing.
        shop.askAfterRead = CoinsAsk(missing: needed - have, retry: ShopOrder(purchase))
      case .alreadyOwned, .giftTaken, .bonusTaken, .collectionIncomplete, .unavailable, .signedOut:
        if purchase.kind != .treat { shop.moment = .refused(purchase) }
      }
      let request = shop.read()
      return (.open(shop), [.fetch(request: request)])

    case .wishToggled(let itemID, let wished):
      if wished {
        shop.mirror.wishlist.insert(itemID)
      } else {
        shop.mirror.wishlist.remove(itemID)
      }
      return (
        .open(shop),
        [.mirrorWish(itemID: itemID, wished: wished), .wish(itemID: itemID, wished: wished)]
      )
    case .wished(let response):
      shop.apply(response)
      return (.open(shop), [.mirror(shop.mirror)])
    case .wishFailed:
      let request = shop.read()
      return (.open(shop), [.fetch(request: request)])

    case .giftTapped(let day):
      guard shop.gift == .idle, shop.giftDay != day else { return (state, []) }
      shop.gift = .opening(day: day)
      return (.open(shop), [.openGift])
    case .giftOpened(let reward, let response):
      guard case .opening(let day) = shop.gift else { return (state, []) }
      shop.apply(response)
      if shop.giftDay == nil { shop.giftDay = day }
      shop.gift = .opened(reward)
      return (.open(shop), [.mirror(shop.mirror)])
    case .giftFailed(let error):
      guard case .opening(let day) = shop.gift else { return (state, []) }
      switch error {
      case .giftTaken(let taken): shop.giftDay = taken
      case .notEnoughCoins, .alreadyOwned, .bonusTaken, .collectionIncomplete, .unavailable,
        .signedOut:
        break
      }
      let request = shop.read()
      shop.gift = .checking(day: day, request: request)
      return (.open(shop), [.fetch(request: request)])
    case .giftShown:
      switch shop.gift {
      case .opened, .taken, .failed: shop.gift = .idle
      case .idle, .opening, .checking: return (state, [])
      }
      return (.open(shop), [])

    case .bonusTapped(let collection, let itemIDs):
      guard shop.bonus == .idle, !shop.bonuses.contains(collection),
        itemIDs.allSatisfy(shop.owned.contains)
      else { return (state, []) }
      shop.bonus = .claiming(collection: collection)
      return (.open(shop), [.claimBonus(collection: collection)])
    case .bonusClaimed(let response):
      guard case .claiming(let collection) = shop.bonus else { return (state, []) }
      shop.apply(response)
      shop.bonus = .claimed(collection: collection)
      return (.open(shop), [.mirror(shop.mirror)])
    case .bonusFailed(let error):
      guard case .claiming(let collection) = shop.bonus else { return (state, []) }
      switch error {
      case .bonusTaken: shop.bonuses.insert(collection)
      case .notEnoughCoins, .alreadyOwned, .giftTaken, .collectionIncomplete, .unavailable,
        .signedOut:
        break
      }
      let request = shop.read()
      shop.bonus = .refusing(collection: collection, request: request)
      return (.open(shop), [.fetch(request: request)])
    case .bonusShown:
      switch shop.bonus {
      case .claimed, .refused: shop.bonus = .idle
      case .idle, .claiming, .refusing: return (state, [])
      }
      return (.open(shop), [])

    case .fetched(let response, let request):
      guard shop.fetch == .reading(request: request) else { return (state, []) }
      shop.fetch = .idle
      shop.apply(response)
      shop.settleChecks(request: request)
      return (.open(shop), [.mirror(shop.mirror)])
    case .fetchFailed(let request):
      guard shop.fetch == .reading(request: request) else { return (state, []) }
      shop.fetch = .idle
      shop.settleChecks(request: request)
      return (.open(shop), [])
    case .inksLoaded(let inks):
      shop.inkLoad = .idle
      if !inks.isEmpty { shop.inks = inks }
      return (.open(shop), [])
    case .inksFailed:
      shop.inkLoad = .idle
      return (.open(shop), [])

    case .coinsAsked(let ask):
      shop.ask = ask
      return (.open(shop), [])
    case .coinsSheetClosed:
      shop.ask = nil
      return (.open(shop), [])
    case .earnAsked(let event):
      return (state, [.earn(event)])
    case .earned(let balance):
      shop.mirror.balance = balance
      return (.open(shop), [.mirrorBalance(balance)])
    case .historyAsked(let limit):
      shop.historyLoad = .loading(limit: limit)
      return (.open(shop), [.loadHistory(limit: limit)])
    case .historyLoaded(let entries, let balance):
      guard shop.historyLoad != .idle else { return (state, []) }
      shop.historyLoad = .idle
      shop.history = entries
      shop.mirror.balance = balance
      return (.open(shop), [.mirrorBalance(balance)])
    case .historyFailed:
      shop.historyLoad = .idle
      return (.open(shop), [])
    }
  }

  /// `YYYY-MM-DD` on this phone's calendar, the day the server counts the gift on.
  public static func localDay(_ date: Date, calendar: Calendar = .current) -> String {
    let day = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
  }

  public static func utcOffset(at date: Date) -> Int { TimeZone.current.secondsFromGMT(for: date) }
}

extension ShopMachine.PairShop {
  /// A gift or bonus refused, or a buy outspent, waits for the room to be read again before the
  /// card or the Coins sheet shows it.
  fileprivate mutating func settleChecks(request: Int) {
    if let waiting = askAfterRead {
      ask = waiting
      askAfterRead = nil
    }
    if case .checking(let day, request) = gift {
      gift = giftDay == day ? .taken : .failed
    }
    if case .refusing(let collection, request) = bonus {
      bonus = .refused(collection: collection)
    }
  }
}
