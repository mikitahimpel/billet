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

  /// True while a scene is open for changes, so the screen around it can step back.
  public var isRenovating = false

  /// Counts up each time the host asks the scene to open for changes from its own control.
  public private(set) var openRequests = 0

  /// Asks the scene to open for changes, for a host that keeps the scene's own button hidden.
  public func requestOpen() {
    openRequests += 1
  }

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

  /// Records where a placed piece was set down, and the way it faces: `yaw` when given, else the
  /// way it already faced.
  public func moved(
    placement id: RoomLayout.Placement.ID, x: Double, z: Double, yaw: Double? = nil
  ) {
    guard let placement = store.state.layout.placements.first(where: { $0.id == id }) else {
      return
    }
    // Only an unknown placement can fail, and the lookup above has just found this one.
    try? store.move(placement: id, x: x, z: z, yaw: yaw ?? placement.yaw)
  }

  /// The stamps there are to spend on unlocking styles.
  public var stamps: Int { store.stamps }

  /// Whether `item` can be chosen in the Style tab: it is free, or it has been unlocked.
  public func hasUnlocked(_ item: RoomStyleItem) -> Bool {
    guard let shopItem = item.shopItem else { return true }
    return store.state.owns(shopItem)
  }

  /// Pays for `item` so it can be chosen from now on. A free or unlocked one costs nothing.
  public func unlock(_ item: RoomStyleItem) throws(ShopError) {
    guard let shopItem = item.shopItem, !hasUnlocked(item) else { return }
    try store.buy(shopItem, transaction: store.newTransaction())
  }

  /// The pieces of furniture waiting in the closet, in the catalog's order.
  public var closetFurniture: [ShopItem] {
    store.catalog.items(in: .furniture).filter { store.owned($0) > 0 }
  }

  /// How many of `item` the closet holds.
  public func owned(_ item: ShopItem) -> Int { store.owned(item) }

  /// The placement `id`, if it is in the room.
  public func placement(_ id: RoomLayout.Placement.ID) -> RoomLayout.Placement? {
    store.state.layout.placements.first { $0.id == id }
  }

  /// Stands `item` from the closet in the room at `spot`, turned by `yaw`, or at an open spot when
  /// `spot` is `nil`. Returns the new placement. Unlike ``renovate(_:)`` this leaves the scene as
  /// it is, for a scene that is already open for changes.
  @discardableResult
  public func place(
    _ item: ShopItem, at spot: (x: Double, z: Double)? = nil, yaw: Double = 0
  ) throws(ShopError) -> RoomLayout.Placement.ID {
    let transaction = store.newTransaction()
    var target = spot
    if target == nil { target = try self.spot(for: item) }
    try store.place(item, transaction: transaction, at: target)
    let id = "placed-\(transaction)"
    if yaw != 0, let placed = placement(id) {
      try store.move(placement: id, x: placed.x, z: placed.z, yaw: yaw)
    }
    return id
  }

  /// Takes the placement `id` out of the room and back into the closet.
  public func putAway(_ id: RoomLayout.Placement.ID) throws(ShopError) {
    try store.remove(placement: id, transaction: store.newTransaction())
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
