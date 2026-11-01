/// What the closet asks of the room when an item is used.
public enum RenovationRequest: Hashable, Sendable {
  /// Cover a wall or the floor with an owned material.
  case paint(ShopItem)
  /// Stand a piece of furniture from the closet in the room.
  case place(ShopItem)
  /// Take a placed piece out of the room and back into the closet.
  case putAway(placement: RoomLayout.Placement.ID)
}

/// The seam between the closet and whatever lets the user arrange the room.
///
/// A renovate mode conforms to this, takes the request, and commits the result to the
/// ``ShopStore`` itself: it places furniture with `place(_:transaction:at:)` once the piece is
/// dropped, and paints with `paint(_:transaction:)`. Until one exists, ``DirectRenovator`` commits
/// at once.
@MainActor
public protocol RoomRenovating {
  func renovate(_ request: RenovationRequest) throws(ShopError)
}

/// Commits every request straight to the layout, putting furniture on the next open spot.
@MainActor
public struct DirectRenovator: RoomRenovating {
  private let store: ShopStore

  public init(store: ShopStore) {
    self.store = store
  }

  public func renovate(_ request: RenovationRequest) throws(ShopError) {
    let transaction = store.newTransaction()
    switch request {
    case .paint(let item): try store.paint(item, transaction: transaction)
    case .place(let item): try store.place(item, transaction: transaction)
    case .putAway(let id): try store.remove(placement: id, transaction: transaction)
    }
  }
}
