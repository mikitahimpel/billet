import Foundation
import Observation

/// One tap to buy: the stamps go at once, and the purchase can be taken back for a few seconds
/// instead of being confirmed first. A piece the room has no open spot for waits in the closet.
@MainActor
@Observable
public final class ShopCheckout {
  public struct Receipt: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
      case forUs
      /// Wrapped and sent, with the note, once it can no longer be taken back.
      case gift(note: String?)
    }

    /// The transaction ID.
    public let id: String
    public let items: [ShopItem]
    public let price: Int
    /// Where its pieces were stood in the room, those that were.
    public let placements: [RoomLayout.Placement.ID]
    /// The room's style before the purchase changed it, when it did.
    public let styleBefore: RoomStyle?
    public let bundle: ShopBundle?
    public let kind: Kind

    /// The first of a bundle's.
    public var item: ShopItem { items[0] }
    public var placement: RoomLayout.Placement.ID? { placements.first }

    /// Pieces that went to the closet because the room had no open spot.
    public var needsPlacing: Bool {
      kind == .forUs && items.filter(\.isPlaceable).count > placements.count
    }
  }

  public enum Outcome: Hashable, Sendable {
    case bought(Receipt)
    /// Not enough stamps: this many more are needed.
    case short(by: Int)
    case owned
    /// The shop refused it for another reason; nothing changed.
    case refused
  }

  public static let undoWindow = Duration.seconds(5)
  /// In characters.
  public static let noteLimit = 80

  /// The latest purchase, while it can still be taken back.
  public private(set) var latest: Receipt?

  private let store: ShopStore
  private let renovator: RoomRenovator
  private let style: @MainActor () -> RoomStyle
  private let restyle: @MainActor (RoomStyle) -> Void
  private let send: @MainActor (ShopItem, String?) -> Void

  /// - Parameters:
  ///   - style: The room's style now, which a bought window view is put into.
  ///   - send: Wraps an item from the closet for the partner, with a note.
  public init(
    store: ShopStore,
    renovator: RoomRenovator,
    style: @escaping @MainActor () -> RoomStyle = { .standard },
    restyle: @escaping @MainActor (RoomStyle) -> Void = { _ in },
    send: @escaping @MainActor (ShopItem, String?) -> Void = { _, _ in }
  ) {
    self.store = store
    self.renovator = renovator
    self.style = style
    self.restyle = restyle
    self.send = send
  }

  public func shortfall(for item: ShopItem) -> Int {
    shortfall(price: item.price)
  }

  public func shortfall(price: Int) -> Int {
    max(price - store.stamps, 0)
  }

  public func isOwned(_ item: ShopItem) -> Bool {
    item.ownsAtMostOne && store.state.owns(item)
  }

  /// How many of `item` the closet holds for the room: a gift wrapped for the partner and about
  /// to go is not counted.
  public func owned(_ item: ShopItem) -> Int {
    var wrapping = 0
    if let latest, case .gift = latest.kind, latest.item.id == item.id { wrapping = 1 }
    return max(store.owned(item) - wrapping, 0)
  }

  /// What is left to buy of `bundle`, and what it costs: an item that can only be owned once and
  /// already is, is left out and not charged for.
  public func remaining(of bundle: ShopBundle) -> (items: [ShopItem], price: Int, sum: Int) {
    let items = bundle.remaining(in: store.catalog, owns: store.state.owns)
    return (items, bundle.price(of: items), ShopBundle.sum(of: items))
  }

  public func buy(_ item: ShopItem) -> Outcome {
    purchase([item], price: item.price, bundle: nil, kind: .forUs)
  }

  public func buy(_ deal: ShopDeal) -> Outcome {
    purchase([deal.item], price: deal.price, bundle: nil, kind: .forUs)
  }

  public func buy(_ bundle: ShopBundle) -> Outcome {
    let left = remaining(of: bundle)
    guard !left.items.isEmpty else { return .owned }
    return purchase(left.items, price: left.price, bundle: bundle, kind: .forUs)
  }

  /// Buys `item` for the partner, at `price` or its own. Only what can be wrapped, a piece or a
  /// treat, can be given; a style is the room's, not a thing.
  public func give(_ item: ShopItem, price: Int? = nil, note: String?) -> Outcome {
    guard !item.ownsAtMostOne else { return .refused }
    let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.noteLimit)
    let kept = trimmed.flatMap { $0.isEmpty ? nil : String($0) }
    return purchase([item], price: price ?? item.price, bundle: nil, kind: .gift(note: kept))
  }

  /// Returns whether it was taken back: only the latest purchase can be.
  @discardableResult
  public func undo(_ receipt: Receipt) -> Bool {
    guard latest?.id == receipt.id else { return false }
    latest = nil
    do {
      try store.undoBuy(
        receipt.items, transaction: receipt.id, placements: receipt.placements,
        bundle: receipt.bundle?.id)
    } catch {
      return false
    }
    if let before = receipt.styleBefore, style() != before {
      let choices = receipt.items.compactMap(\.styleChoice)
      if choices.contains(where: style().shows) { restyle(before) }
    }
    return true
  }

  /// A gift goes to the partner then.
  public func settle(_ receipt: Receipt) {
    guard latest?.id == receipt.id else { return }
    latest = nil
    if case .gift(let note) = receipt.kind { send(receipt.item, note) }
  }

  private func purchase(
    _ items: [ShopItem], price: Int, bundle: ShopBundle?, kind: Receipt.Kind
  ) -> Outcome {
    if items.count == 1, bundle == nil, isOwned(items[0]) { return .owned }
    let short = shortfall(price: price)
    if short > 0 { return .short(by: short) }
    // A purchase still open is settled first: only the latest one can be taken back.
    if let previous = latest { settle(previous) }
    let transaction = store.newTransaction()
    do {
      let outcome = try store.buy(
        items, price: price, transaction: transaction, bundle: bundle?.id)
      guard outcome == .applied else { return .refused }
    } catch {
      switch error {
      case .notEnoughStamps(let needed, let have): return .short(by: max(needed - have, 1))
      case .alreadyOwned: return .owned
      case .unknownItem, .notInCloset, .wrongKind, .roomIsFull, .unknownPlacement,
        .unknownPurchase:
        return .refused
      }
    }
    var placements: [RoomLayout.Placement.ID] = []
    var styleBefore: RoomStyle?
    if kind == .forUs {
      for item in items where item.isPlaceable {
        if let placement = place(item) { placements.append(placement) }
      }
      let choices = items.compactMap(\.styleChoice)
      if !choices.isEmpty {
        let before = style()
        let after = choices.reduce(before) { $0.with($1) }
        if after != before {
          styleBefore = before
          restyle(after)
        }
      }
    }
    let receipt = Receipt(
      id: transaction, items: items, price: price, placements: placements,
      styleBefore: styleBefore, bundle: bundle, kind: kind)
    latest = receipt
    return .bought(receipt)
  }

  /// Shows a style already owned, or free, in the room.
  public func use(_ choice: RoomStyleItem) {
    guard choice.shopItem.map(isOwned) ?? true else { return }
    let before = style()
    let after = before.with(choice)
    if after != before { restyle(after) }
  }

  /// `nil` when it stays in the closet because the room has no open spot.
  private func place(_ item: ShopItem) -> RoomLayout.Placement.ID? {
    let before = Set(store.state.layout.placements.map(\.id))
    do {
      try renovator.renovate(.place(item))
    } catch {
      return nil
    }
    return store.state.layout.placements.first { !before.contains($0.id) }?.id
  }
}
