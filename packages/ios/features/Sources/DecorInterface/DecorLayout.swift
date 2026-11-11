import Foundation

/// Where a piece stands: a wall or the floor, on a grid so a drag snaps and two pieces line up.
/// Cells count from the room's middle; a cell is ``DecorGrid/step`` metres.
public struct Placement: Codable, Equatable, Hashable, Sendable {
  public enum Surface: String, Codable, Sendable, CaseIterable {
    case floor
    /// The wall behind the cat tree, along x.
    case backWall
    /// The wall with the window, along z.
    case leftWall
  }

  public var item: String
  public var surface: Surface
  /// Across the room on the floor and the back wall (x); along the left wall (z).
  public var u: Int
  /// Into the room on the floor (z); unused on a wall.
  public var v: Int
  /// Turns of 90 degrees, 0 to 3. A wall piece faces out of its wall and has none.
  public var quarterTurns: Int

  public init(item: String, surface: Surface, u: Int, v: Int = 0, quarterTurns: Int = 0) {
    self.item = item
    self.surface = surface
    self.u = u
    self.v = v
    self.quarterTurns = ((quarterTurns % 4) + 4) % 4
  }

  /// The same piece one turn on, or itself on a wall.
  public var turned: Placement {
    var next = self
    if surface == .floor { next.quarterTurns = (quarterTurns + 1) % 4 }
    return next
  }

  public func moved(to surface: Surface, u: Int, v: Int) -> Placement {
    var next = self
    next.surface = surface
    next.u = u
    next.v = surface == .floor ? v : 0
    if surface != .floor { next.quarterTurns = 0 }
    return next
  }
}

public enum DecorGrid {
  /// Metres between two cells.
  public static let step = 0.05
  /// The floor and the walls are -0.49 to 0.49 across a piece's edges.
  public static let reach = 0.49
  /// A wall piece hangs this high, to its middle.
  public static let wallHeight = 0.45

  public static func metres(_ cell: Int) -> Double { Double(cell) * step }

  public static func cell(_ metres: Double) -> Int { Int((metres / step).rounded()) }
}

/// A rectangle on the floor, or a stretch of wall, in metres: its middle and half-extents.
struct Span: Equatable {
  var x: Double
  var z: Double
  var halfX: Double
  var halfZ: Double

  func overlaps(_ other: Span) -> Bool {
    abs(x - other.x) < halfX + other.halfX - 0.001 && abs(z - other.z) < halfZ + other.halfZ - 0.001
  }
}

/// What the player placed, and what they put back on purpose. A piece in neither is new: owned and
/// not yet put anywhere, so it goes into the room by itself.
public struct DecorLayout: Codable, Equatable, Sendable {
  /// Most pieces one room holds, so its draw cost stays bounded however many the shop sells.
  public static let maxPlaced = 8

  public private(set) var placements: [Placement]
  /// Owned pieces the player or a full room left in the closet.
  public private(set) var stored: Set<String>

  public init(placements: [Placement] = [], stored: Set<String> = DecorItem.starters) {
    self.placements = placements
    self.stored = stored
  }

  public func placement(of item: String) -> Placement? {
    placements.first { $0.item == item }
  }

  public func isPlaced(_ item: String) -> Bool { placement(of: item) != nil }

  /// Why a placement does not fit, or that it does.
  public enum Verdict: Equatable, Sendable {
    case fits
    /// The wrong kind of surface, or an unknown piece.
    case wrongSurface
    case outsideRoom
    /// On the room's own furniture or on another piece.
    case occupied
    /// It would cut her off from where she goes, or leave her too little floor.
    case blocksWay
  }

  public func accepts(_ placement: Placement, in room: DecorRoom = .home) -> Bool {
    verdict(placement, in: room) == .fits
  }

  /// Whether `placement` fits: inside the room, clear of the room's own furniture and of every other
  /// piece on the same surface, and leaving her a way to everywhere she goes. A flat piece and what
  /// stands on it share their floor.
  public func verdict(_ placement: Placement, in room: DecorRoom = .home) -> Verdict {
    guard let item = DecorItem.item(shopID: placement.item),
      (item.mount == .wall) == (placement.surface != .floor),
      let span = Self.span(of: placement, item: item)
    else { return .wrongSurface }
    switch placement.surface {
    case .floor:
      guard abs(span.x) + span.halfX <= DecorGrid.reach + 0.001,
        abs(span.z) + span.halfZ <= DecorGrid.reach + 0.001
      else { return .outsideRoom }
      if !item.isFlat, room.blocked.contains(where: span.overlaps) { return .occupied }
    case .backWall, .leftWall:
      guard abs(span.x) + span.halfX <= DecorGrid.reach + 0.001 else { return .outsideRoom }
      if room.blockedWall(placement.surface).contains(where: { $0.overlaps(span) }) {
        return .occupied
      }
    }
    for other in placements where other.item != placement.item && other.surface == placement.surface
    {
      guard let otherItem = DecorItem.item(shopID: other.item),
        let otherSpan = Self.span(of: other, item: otherItem)
      else { continue }
      if placement.surface == .floor, item.isFlat || otherItem.isFlat { continue }
      if span.overlaps(otherSpan) { return .occupied }
    }
    if placement.surface == .floor, !item.isFlat {
      let occupancy = putting(placement).occupancy(in: room)
      if occupancy.bareShare < room.minimumFree
        || !occupancy.connects(from: room.spawn, to: room.anchors)
      {
        return .blocksWay
      }
    }
    return .fits
  }

  /// The floor she cannot walk through with this layout.
  public func occupancy(in room: DecorRoom = .home) -> Occupancy {
    let solid = placements.compactMap { placement -> Span? in
      guard placement.surface == .floor, let item = DecorItem.item(shopID: placement.item),
        !item.isFlat
      else { return nil }
      return Self.span(of: placement, item: item)
    }
    return room.occupancy(solid: solid)
  }

  /// Whether she can still walk from her bed to where she stands for the visit `name`.
  public func canVisit(_ name: String, in room: DecorRoom = .home) -> Bool {
    guard let stop = room.visits[name] else { return false }
    let here = occupancy(in: room)
    // She walks round what is in the way, so the visit is open while a way to the stop is.
    let spot = room.occupancy(solid: []).nearestFree(to: stop) ?? stop
    return here.connects(from: room.spawn, to: [spot])
  }

  /// The closest spot to `placement`, on the same surface, where it fits; nil when none does.
  public func nearestFit(to placement: Placement, in room: DecorRoom = .home) -> Placement? {
    let reach = Occupancy.reach
    let candidates = (-reach...reach).flatMap { v in
      (-reach...reach).map { u in
        placement.moved(to: placement.surface, u: u, v: placement.surface == .floor ? v : 0)
      }
    }
    return
      candidates
      .filter { placement.surface == .floor || $0.v == 0 }
      .sorted {
        distance($0, placement) < distance($1, placement)
      }
      .first { accepts($0, in: room) }
  }

  private func distance(_ a: Placement, _ b: Placement) -> Int {
    (a.u - b.u) * (a.u - b.u) + (a.v - b.v) * (a.v - b.v)
  }

  /// On a wall the span runs along its x, whichever wall it is.
  static func span(of placement: Placement, item: DecorItem) -> Span? {
    switch placement.surface {
    case .floor:
      let turned = placement.quarterTurns.isMultiple(of: 2) == false
      let width = turned ? item.depth : item.width
      let depth = turned ? item.width : item.depth
      return Span(
        x: DecorGrid.metres(placement.u), z: DecorGrid.metres(placement.v), halfX: width / 2,
        halfZ: depth / 2)
    case .backWall, .leftWall:
      return Span(x: DecorGrid.metres(placement.u), z: 0, halfX: item.width / 2, halfZ: 0.01)
    }
  }

  /// Where a new piece goes by itself: the first open spot of a short list, then a sweep of the floor.
  public func defaultPlacement(for itemID: String, in room: DecorRoom = .home) -> Placement? {
    guard let item = DecorItem.item(shopID: itemID) else { return nil }
    let candidates: [Placement]
    switch item.mount {
    case .floor:
      let preferred = room.floorSpots.map {
        Placement(item: itemID, surface: .floor, u: $0.u, v: $0.v)
      }
      let sweep = (-9...9).flatMap { v in
        (-9...9).map { u in Placement(item: itemID, surface: .floor, u: u, v: v) }
      }
      candidates = preferred + sweep
    case .wall:
      candidates = [Placement.Surface.backWall, .leftWall].flatMap { surface in
        (-9...9).map { Placement(item: itemID, surface: surface, u: $0) }
      }
    }
    return candidates.first { accepts($0, in: room) }
  }

  /// Puts every owned piece the layout has never met into the room, where it fits, else in the closet.
  public func settled(owned: Set<String>, in room: DecorRoom = .home) -> DecorLayout {
    var next = self
    for item in DecorItem.placeable(among: owned)
    where !next.isPlaced(item.id) && !next.stored.contains(item.id) {
      if next.placements.count < Self.maxPlaced,
        let spot = next.defaultPlacement(for: item.id, in: room)
      {
        next.placements.append(spot)
      } else {
        next.stored.insert(item.id)
      }
    }
    return next
  }

  /// The same closet with these placements, as the server holds them.
  public func replacing(placements spots: [Placement]) -> DecorLayout {
    var next = self
    next.placements = spots
    next.stored.subtract(spots.map(\.item))
    return next
  }

  /// A placement for `item`, replacing where it stood.
  public func putting(_ placement: Placement) -> DecorLayout {
    var next = self
    if let index = next.placements.firstIndex(where: { $0.item == placement.item }) {
      next.placements[index] = placement
    } else {
      next.placements.append(placement)
    }
    next.stored.remove(placement.item)
    return next
  }

  public func storing(_ item: String) -> DecorLayout {
    var next = self
    next.placements.removeAll { $0.item == item }
    next.stored.insert(item)
    return next
  }

  /// Owned pieces not standing in the room, the ones put away first, then the shop's order.
  public func closet(owned: Set<String>) -> [DecorItem] {
    let waiting = DecorItem.placeable(among: owned).filter { !isPlaced($0.id) }
    return waiting.filter { stored.contains($0.id) } + waiting.filter { !stored.contains($0.id) }
  }

  public func closetCount(owned: Set<String>) -> Int { closet(owned: owned).count }

  /// Owned pieces standing in the room.
  public func placedCount(owned: Set<String>) -> Int {
    placements.filter { owned.contains($0.item) }.count
  }

  /// Without a placement of something no longer owned, such as a gift taken back.
  public func keeping(owned: Set<String>) -> DecorLayout {
    var next = self
    next.placements.removeAll { !owned.contains($0.item) }
    return next
  }
}
