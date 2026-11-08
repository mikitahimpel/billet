import Foundation
import Wire

/// What one tap in the Shop buys: one item, a set's pieces, an ink or a treat. `cost` is the price
/// shown; the server charges its own.
public struct ShopOrder: Hashable, Sendable {
  public let offer: ShopOffer
  public let itemIDs: [String]
  public let cost: Int
  public let title: String
  public var kind = Purchase.Kind.item
  /// Bought for the partner: it arrives wrapped and they unwrap it.
  public var asGift = false

  public init(
    offer: ShopOffer, itemIDs: [String], cost: Int, title: String, kind: Purchase.Kind = .item,
    asGift: Bool = false
  ) {
    self.offer = offer
    self.itemIDs = itemIDs
    self.cost = cost
    self.title = title
    self.kind = kind
    self.asGift = asGift
  }

  public init(_ purchase: Purchase) {
    self.init(
      offer: purchase.offer, itemIDs: purchase.itemIDs, cost: purchase.cost, title: purchase.title,
      kind: purchase.kind, asGift: purchase.asGift)
  }

  public static func treat(price: Int) -> ShopOrder {
    ShopOrder(offer: .treat, itemIDs: [], cost: price, title: "A treat", kind: .treat)
  }
}

/// One buy in the Shop, shown on the phone from the tap until the server answers: the purchase
/// moment plays for it, it offers Undo for a few seconds, and only then is it ordered.
public struct Purchase: Identifiable, Hashable, Sendable {
  /// Made once per tap; its string is the order's idempotency key on every retry.
  public let id: UUID
  public let offer: ShopOffer
  /// What the couple bought: one item, or a set's pieces.
  public let itemIDs: [String]
  /// The pieces this buy adds; pieces owned before stay owned when it is undone or refused.
  public let added: [String]
  /// The price shown; the server charges its own.
  public let cost: Int
  public let date: Date
  public var title: String
  public var kind = Kind.item
  /// Bought for the partner: it arrives wrapped and they unwrap it.
  public var asGift = false
  public var stage = Stage.undoable

  public init(
    id: UUID = UUID(), offer: ShopOffer, itemIDs: [String], added: [String], cost: Int, date: Date,
    title: String, kind: Kind = .item, asGift: Bool = false, stage: Stage = .undoable
  ) {
    self.id = id
    self.offer = offer
    self.itemIDs = itemIDs
    self.added = added
    self.cost = cost
    self.date = date
    self.title = title
    self.kind = kind
    self.asGift = asGift
    self.stage = stage
  }

  public init(_ order: ShopOrder, id: UUID, added: [String], at date: Date, stage: Stage) {
    self.init(
      id: id, offer: order.offer, itemIDs: order.itemIDs, added: added, cost: order.cost,
      date: date, title: order.title, kind: order.kind, asGift: order.asGift, stage: stage)
  }

  public enum Kind: Hashable, Sendable {
    /// Room pieces.
    case item
    /// An ink colour for notes and drawings.
    case ink
    /// A treat for the cat: no purchase moment and no Undo.
    case treat
  }

  /// Where the buy is between the tap and the server's answer.
  public enum Stage: Hashable, Sendable {
    /// Shown, Undo offered, not yet ordered.
    case undoable
    /// The Undo window passed (a treat has none): the order is on its way.
    case ordering
  }

  public static let undoWindow: TimeInterval = 5

  public var key: IdempotencyKey { IdempotencyKey(id.uuidString) }

  public func canUndo(at now: Date) -> Bool {
    kind != .treat && now.timeIntervalSince(date) < Self.undoWindow
  }
}

/// Why the Coins sheet is open: `missing` is what a buy needed beyond the balance, 0 when the
/// header's coins opened it, and `retry` is that buy, to finish in one tap once the coins are there.
public struct CoinsAsk: Identifiable, Hashable, Sendable {
  public let id: UUID
  public let missing: Int
  public let retry: ShopOrder?

  public typealias Retry = ShopOrder

  public init(id: UUID = UUID(), missing: Int, retry: ShopOrder?) {
    self.id = id
    self.missing = missing
    self.retry = retry
  }
}
