import Observation

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
@MainActor
public protocol RoomRenovating {
  func renovate(_ request: RenovationRequest) throws(ShopError)
}

/// Carries the closet's requests to the room a scene shows, and what the scene changes back to the
/// ``ShopStore``.
///
/// A piece goes to an open spot at once, so nothing is lost if the user walks away, and the scene
/// then lets them move it. A scene without renovate mode leaves ``openSpot`` unset and the store
/// picks the spot.
@MainActor
@Observable
public final class RoomRenovator: RoomRenovating {
  private let store: ShopStore

  /// Counts up each time a piece goes into the room. A scene opens for changes on each one.
  public private(set) var placements = 0

  /// Finds room for a floor piece in the scene's own plan; `nil` from it means the room is full.
  @ObservationIgnored public var openSpot: ((ShopItem) -> (x: Double, z: Double)?)?

  public init(store: ShopStore) {
    self.store = store
  }

  public func renovate(_ request: RenovationRequest) throws(ShopError) {
    let transaction = store.newTransaction()
    switch request {
    case .paint(let item):
      try store.paint(item, transaction: transaction)
    case .place(let item):
      try store.place(item, transaction: transaction, at: try spot(for: item))
      placements += 1
    case .putAway(let id):
      try store.remove(placement: id, transaction: transaction)
    }
  }

  /// Records where a placed piece was set down, keeping the way it faces.
  public func moved(placement id: RoomLayout.Placement.ID, x: Double, z: Double) {
    guard let placement = store.state.layout.placements.first(where: { $0.id == id }) else {
      return
    }
    // Only an unknown placement can fail, and the lookup above has just found this one.
    try? store.move(placement: id, x: x, z: z, yaw: placement.yaw)
  }

  /// Takes the shop's material off `surface`, because the scene has painted over it.
  public func cleared(_ surface: RoomSurface) {
    store.clearPaint(on: surface)
  }

  private func spot(for item: ShopItem) throws(ShopError) -> (x: Double, z: Double)? {
    guard case .furniture(_, _, _, .floor) = item.look, let openSpot else { return nil }
    guard let spot = openSpot(item) else { throw .roomIsFull }
    return spot
  }
}
