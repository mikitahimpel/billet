import Observation

/// One tap to buy: the stamps go at once, the item lands where it belongs, and the purchase can be
/// taken back for a few seconds instead of being confirmed first.
///
/// A piece of furniture is stood in the room through the ``RoomRenovator``; when the room has no
/// open spot it waits in the closet and the receipt says it still needs placing. A window view is
/// unlocked and shown at once.
@MainActor
@Observable
public final class ShopCheckout {
  /// A purchase that has just gone through.
  public struct Receipt: Identifiable, Hashable, Sendable {
    /// The purchase's transaction ID.
    public let id: String
    public let item: ShopItem
    /// Where it was stood in the room, when it was.
    public let placement: RoomLayout.Placement.ID?
    /// The room's style before the purchase changed it, when it did.
    public let styleBefore: RoomStyle?

    /// A piece that went to the closet because the room had no open spot.
    public var needsPlacing: Bool { item.isPlaceable && placement == nil }
  }

  /// What a tap on a price did.
  public enum Outcome: Hashable, Sendable {
    case bought(Receipt)
    /// Not enough stamps: this many more are needed.
    case short(by: Int)
    /// It can only be owned once, and it is.
    case owned
    /// The shop refused it for another reason; nothing changed.
    case refused
  }

  /// How long a purchase can be taken back.
  public static let undoWindow = Duration.seconds(5)

  /// The latest purchase, while it can still be taken back.
  public private(set) var latest: Receipt?

  private let store: ShopStore
  private let renovator: RoomRenovator
  private let style: @MainActor () -> RoomStyle
  private let restyle: @MainActor (RoomStyle) -> Void

  /// - Parameters:
  ///   - style: The room's style now, which a bought window view is put into.
  ///   - restyle: Shares a new style of the room.
  public init(
    store: ShopStore,
    renovator: RoomRenovator,
    style: @escaping @MainActor () -> RoomStyle = { .standard },
    restyle: @escaping @MainActor (RoomStyle) -> Void = { _ in }
  ) {
    self.store = store
    self.renovator = renovator
    self.style = style
    self.restyle = restyle
  }

  /// The stamps still missing for `item`, or 0 when there are enough.
  public func shortfall(for item: ShopItem) -> Int {
    max(item.price - store.stamps, 0)
  }

  /// Whether `item` can only be owned once and is.
  public func isOwned(_ item: ShopItem) -> Bool {
    item.ownsAtMostOne && store.state.owns(item)
  }

  /// Buys `item` with stamps, then places or shows it.
  public func buy(_ item: ShopItem) -> Outcome {
    if isOwned(item) { return .owned }
    let short = shortfall(for: item)
    if short > 0 { return .short(by: short) }
    let transaction = store.newTransaction()
    do {
      guard try store.buy(item, transaction: transaction) == .applied else { return .refused }
    } catch {
      switch error {
      case .notEnoughStamps(let needed, let have): return .short(by: max(needed - have, 1))
      case .alreadyOwned: return .owned
      case .unknownItem, .notInCloset, .wrongKind, .roomIsFull, .unknownPlacement,
        .unknownPurchase:
        return .refused
      }
    }
    var placement: RoomLayout.Placement.ID?
    var styleBefore: RoomStyle?
    switch item.look {
    case .furniture:
      placement = place(item)
    case .style(let choice):
      let before = style()
      let after = before.with(choice)
      if after != before {
        styleBefore = before
        restyle(after)
      }
    case .material, .treat:
      break
    }
    let receipt = Receipt(
      id: transaction, item: item, placement: placement, styleBefore: styleBefore)
    latest = receipt
    return .bought(receipt)
  }

  /// Takes back `receipt`'s purchase if it is still the latest one. Returns whether it was.
  @discardableResult
  public func undo(_ receipt: Receipt) -> Bool {
    guard latest?.id == receipt.id else { return false }
    latest = nil
    do {
      try store.undoBuy(receipt.item, transaction: receipt.id, placement: receipt.placement)
    } catch {
      return false
    }
    if let before = receipt.styleBefore, case .style(let choice) = receipt.item.look,
      style().shows(choice)
    {
      restyle(before)
    }
    return true
  }

  /// Shows a style already owned, or free, in the room.
  public func use(_ choice: RoomStyleItem) {
    guard choice.shopItem.map(isOwned) ?? true else { return }
    let before = style()
    let after = before.with(choice)
    if after != before { restyle(after) }
  }

  /// Ends `receipt`'s chance to be taken back, once its time is up.
  public func settle(_ receipt: Receipt) {
    if latest?.id == receipt.id { latest = nil }
  }

  /// Stands a bought piece in the room. Returns its placement, or `nil` when it stays in the
  /// closet because the room has no open spot.
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
