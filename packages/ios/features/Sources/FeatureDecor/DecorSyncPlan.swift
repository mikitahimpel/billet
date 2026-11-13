import DecorInterface
import Wire

/// What this phone's layout and the server's differ by, as the changes that bring the server to this phone,
/// and the two layouts' wire shapes.
public enum DecorSyncPlan {
  /// One `Place` for each piece that is new or has moved, one `Unplace` for each the server has and this
  /// phone has put away. Nothing when they agree. Both lists are every piece standing in the room, the room's
  /// own furniture at home included (`DecorLayout.allPlacements`), so putting that furniture away is an `Unplace`.
  public static func changes(from server: [Placement], to local: [Placement]) -> [LayoutChange] {
    let known = Dictionary(server.map { ($0.item, $0) }, uniquingKeysWith: { _, last in last })
    var changes: [LayoutChange] = []
    for placement in local where known[placement.item] != placement {
      changes.append(.place(wire(placement)))
    }
    let kept = Set(local.map(\.item))
    for placement in server where !kept.contains(placement.item) {
      changes.append(.unplace(RoomItemId(placement.item)))
    }
    return changes
  }

  public static func wire(_ placement: Placement) -> RoomPlacement {
    RoomPlacement(
      item: RoomItemId(placement.item), surface: placement.surface.rawValue, u: placement.u,
      v: placement.v, quarterTurns: placement.wireTurns,
      room: placement.space == .living ? nil : placement.space.rawValue)
  }

  /// Nil for a placement this build does not know, such as a surface a newer app added.
  public static func placement(_ wire: RoomPlacement) -> Placement? {
    guard let surface = Placement.Surface(rawValue: wire.surface),
      DecorItem.item(shopID: wire.item.rawValue) != nil
    else { return nil }
    var space = DecorSpace.living
    if let room = wire.room {
      guard let known = DecorSpace(rawValue: room) else { return nil }
      space = known
    }
    return Placement(
      item: wire.item.rawValue, surface: surface, u: wire.u, v: wire.v,
      wireTurns: wire.quarterTurns, space: space)
  }

  /// The room's own furniture the server says is put away.
  public static func stowed(_ wire: [RoomItemId]?) -> Set<String>? {
    wire.map { Set($0.map(\.rawValue)) }
  }

  public static func placements(_ wire: [RoomPlacement]) -> [Placement] {
    wire.compactMap(placement)
  }
}
