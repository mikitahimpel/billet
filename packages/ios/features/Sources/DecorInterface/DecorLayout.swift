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
  /// Turns of 45 degrees, 0 to 7. A wall piece faces out of its wall and has none.
  public var eighthTurns: Int
  /// The room it stands in.
  public var space: DecorSpace

  public init(
    item: String, surface: Surface, u: Int, v: Int = 0, eighthTurns: Int,
    space: DecorSpace = .living
  ) {
    self.item = item
    self.surface = surface
    self.u = u
    self.v = v
    self.eighthTurns = ((eighthTurns % 8) + 8) % 8
    self.space = space
  }

  public init(
    item: String, surface: Surface, u: Int, v: Int = 0, quarterTurns: Int = 0,
    space: DecorSpace = .living
  ) {
    self.init(
      item: item, surface: surface, u: u, v: v, eighthTurns: quarterTurns * 2, space: space)
  }

  /// Whole quarter turns, the 45 degrees of a half step left out.
  public var quarterTurns: Int { eighthTurns / 2 }

  /// Whether it stands at 45 degrees to the walls.
  public var isDiagonal: Bool { !eighthTurns.isMultiple(of: 2) }

  /// How far the scene turns it about the up axis.
  public var angle: Double { Double(eighthTurns) * .pi / 4 }

  /// What the server stores: the quarter turns 0 to 3 as they always were, plus 4 for a further 45 degrees,
  /// so a layout kept before fine turns reads the same.
  public var wireTurns: Int { eighthTurns / 2 + (isDiagonal ? 4 : 0) }

  public init(
    item: String, surface: Surface, u: Int, v: Int = 0, wireTurns: Int, space: DecorSpace = .living
  ) {
    self.init(
      item: item, surface: surface, u: u, v: v,
      eighthTurns: (wireTurns % 4) * 2 + (wireTurns >= 4 ? 1 : 0), space: space)
  }

  /// The same piece a quarter turn on, or itself on a wall.
  public var turned: Placement { turned(byEighths: 2) }

  /// The same piece `eighths` turns of 45 degrees on, or itself on a wall.
  public func turned(byEighths eighths: Int) -> Placement {
    var next = self
    if surface == .floor { next.eighthTurns = ((eighthTurns + eighths) % 8 + 8) % 8 }
    return next
  }

  private enum CodingKeys: String, CodingKey { case item, surface, u, v, quarterTurns, room }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      item: try values.decode(String.self, forKey: .item),
      surface: try values.decode(Surface.self, forKey: .surface),
      u: try values.decode(Int.self, forKey: .u), v: try values.decode(Int.self, forKey: .v),
      wireTurns: try values.decode(Int.self, forKey: .quarterTurns),
      space: try values.decodeIfPresent(DecorSpace.self, forKey: .room) ?? .living)
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(item, forKey: .item)
    try values.encode(surface, forKey: .surface)
    try values.encode(u, forKey: .u)
    try values.encode(v, forKey: .v)
    try values.encode(wireTurns, forKey: .quarterTurns)
    if space != .living { try values.encode(space, forKey: .room) }
  }

  public func moved(to surface: Surface, u: Int, v: Int) -> Placement {
    var next = self
    next.surface = surface
    next.u = u
    next.v = surface == .floor ? v : 0
    if surface != .floor { next.eighthTurns = 0 }
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

/// What the player placed, and what they put back on purpose. A shop piece in neither is new: owned and
/// not yet put anywhere, so it goes into the room by itself. A piece of the room's own furniture in neither
/// stands where the room has it, so a layout that never heard of them is the room as it always was.
public struct DecorLayout: Codable, Equatable, Sendable {
  /// Most pieces the player bought that one room holds, so its draw cost stays bounded however many the
  /// shop sells. The room's own furniture is not counted.
  public static let maxPlaced = 8

  /// What was placed or moved on purpose. The room's furniture still where it stands is not here: see
  /// `standing`.
  public private(set) var placements: [Placement]
  /// Owned pieces, and the room's own furniture, the player or a full room left in the closet.
  public private(set) var stored: Set<String>

  public init(placements: [Placement] = [], stored: Set<String> = DecorItem.starters) {
    self.placements = placements
    self.stored = stored
  }

  /// The room's own furniture that has not been moved or stored, each at its home.
  public var standing: [Placement] {
    DecorItem.baseItems.compactMap { item in
      guard let base = item.base, !stored.contains(item.id),
        !placements.contains(where: { $0.item == item.id })
      else { return nil }
      return Placement(item: item.id, surface: .floor, u: base.u, v: base.v, space: base.space)
    }
  }

  /// Every piece in every room.
  public var allPlacements: [Placement] { standing + placements }

  /// The pieces standing in `room`.
  public func allPlacements(in room: DecorRoom) -> [Placement] {
    allPlacements.filter { $0.space == room.space }
  }

  public func placement(of item: String) -> Placement? {
    allPlacements.first { $0.item == item }
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
      placement.space == room.space, item.base.map({ $0.space == room.space }) ?? true,
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
    for other in allPlacements(in: room)
    where other.item != placement.item && other.surface == placement.surface {
      guard let otherItem = DecorItem.item(shopID: other.item),
        let otherSpan = Self.span(of: other, item: otherItem)
      else { continue }
      if placement.surface == .floor, item.isFlat || otherItem.isFlat { continue }
      if span.overlaps(otherSpan) { return .occupied }
    }
    if placement.surface == .floor, !item.isFlat {
      let next = putting(placement)
      let occupancy = next.occupancy(in: room)
      if occupancy.bareShare < room.minimumFree
        || !next.reachesAnchors(in: room)
      {
        return .blocksWay
      }
    }
    return .fits
  }

  /// The floor she cannot walk through with this layout.
  public func occupancy(in room: DecorRoom = .home) -> Occupancy {
    let solid = allPlacements(in: room).compactMap { placement -> Span? in
      guard placement.surface == .floor, let item = DecorItem.item(shopID: placement.item),
        !item.isFlat
      else { return nil }
      return Self.span(of: placement, item: item)
    }
    return room.occupancy(solid: solid)
  }

  /// Where `follow` is now, or nil while its piece is stored.
  public func point(of follow: DecorFollow) -> Occupancy.Point? {
    guard let placement = placement(of: follow.piece) else { return nil }
    let (dx, dz) = Self.turn(follow.dx, follow.dz, eighthTurns: placement.eighthTurns)
    return (DecorGrid.metres(placement.u) + dx, DecorGrid.metres(placement.v) + dz)
  }

  /// Turns of 45 degrees about the up axis, as the scene turns a piece.
  static func turn(_ x: Double, _ z: Double, eighthTurns: Int) -> (Double, Double) {
    switch eighthTurns % 8 {
    case 2: return (z, -x)
    case 4: return (-x, -z)
    case 6: return (-z, x)
    case 0: return (x, z)
    default:
      let angle = Double(eighthTurns) * .pi / 4
      return (x * cos(angle) + z * sin(angle), -x * sin(angle) + z * cos(angle))
    }
  }

  /// Where she steps down from her bed: beside it while it stands, else beside the bed or sofa she rests on,
  /// else where the room says.
  public func spawn(in room: DecorRoom = .home) -> Occupancy.Point {
    point(of: room.spawnFollow) ?? restSpawn(in: room) ?? room.spawn
  }

  /// Where she steps down from her bed, as a floor point no piece stands on.
  public func spawnSpot(in room: DecorRoom = .home) -> Occupancy.Point {
    let point = spawn(in: room)
    return standing(near: point, beside: room.spawnFollow.piece, in: room, slack: 0.3) ?? point
  }

  /// A floor point she can stand on at `point`: itself while no piece stands on it and no other piece's margin
  /// holds it, else the nearest such cell. `piece` is the piece the stop belongs to, whose own margin is the point
  /// of the stop: she stands beside it, never in it. Nil when none is within `slack` metres.
  public func standing(
    near point: Occupancy.Point, beside piece: String? = nil, in room: DecorRoom = .home,
    slack: Double = 0.15
  ) -> Occupancy.Point? {
    let full = occupancy(in: room)
    let others = piece.map { storing($0).occupancy(in: room) } ?? full
    func fits(_ p: Occupancy.Point) -> Bool { !others.isBlocked(at: p) && !full.isSolid(at: p) }
    if fits(point) { return point }
    let reach = Int((slack / DecorGrid.step).rounded(.up)) + 1
    let u0 = DecorGrid.cell(point.x)
    let v0 = DecorGrid.cell(point.z)
    var best: (point: Occupancy.Point, distance: Double)?
    for v in (v0 - reach)...(v0 + reach) {
      for u in (u0 - reach)...(u0 + reach) {
        let candidate = (DecorGrid.metres(u), DecorGrid.metres(v))
        let distance = hypot(candidate.0 - point.x, candidate.1 - point.z)
        guard distance <= slack, fits(candidate), distance < (best?.distance ?? .infinity) else {
          continue
        }
        best = (candidate, distance)
      }
    }
    return best?.point
  }

  /// The piece she rests on and where she steps down from it.
  public struct CatHome: Equatable, Sendable {
    public let item: String
    public let placement: Placement
    /// Where she sits, on the piece's top.
    public let seat: Occupancy.Point
    /// How high that seat is above the floor, in metres; zero for the room's own bed, which the scene knows.
    public let height: Double
    public let spawn: Occupancy.Point

    public static func == (a: CatHome, b: CatHome) -> Bool {
      a.item == b.item && a.placement == b.placement
    }
  }

  /// The bed or sofa she rests on: the room's own bed while it stands, else the first other by name.
  public func catHome(in room: DecorRoom = .home) -> CatHome? {
    let rests = allPlacements(in: room).filter { DecorItem.item(shopID: $0.item)?.isRest == true }
      .sorted { $0.item < $1.item }
    guard
      let placement = rests.first(where: { $0.item == room.spawnFollow.piece }) ?? rests.first,
      let item = DecorItem.item(shopID: placement.item),
      let span = Self.span(of: placement, item: item)
    else { return nil }
    let own = item.isBase
    return CatHome(
      item: item.id, placement: placement, seat: (span.x, span.z),
      height: own ? 0 : item.height * 0.9, spawn: spawn(in: room))
  }

  private func restSpawn(in room: DecorRoom) -> Occupancy.Point? {
    let rests = allPlacements(in: room).filter { DecorItem.item(shopID: $0.item)?.isRest == true }
      .sorted { $0.item < $1.item }
    guard let placement = rests.first, let item = DecorItem.item(shopID: placement.item),
      let span = Self.span(of: placement, item: item)
    else { return nil }
    let occupancy = occupancy(in: room)
    let middle = occupancy.nearestFree(to: (span.x, span.z)) ?? (span.x, span.z)
    return Self.approach(to: span, in: occupancy, from: middle) ?? middle
  }

  /// Where she walks up to each piece she must always be able to reach, while it stands: the cat tree. Nil
  /// for a piece nothing leaves her a way to.
  public func anchorSpots(in room: DecorRoom = .home) -> [String: Occupancy.Point] {
    let occupancy = occupancy(in: room)
    let spawn = spawn(in: room)
    var spots: [String: Occupancy.Point] = [:]
    for id in room.anchorPieces {
      guard let placement = placement(of: id), let item = DecorItem.item(shopID: id),
        let span = Self.span(of: placement, item: item),
        let spot = Self.approach(to: span, in: occupancy, from: spawn)
      else { continue }
      spots[id] = spot
    }
    return spots
  }

  /// The anchor spots she can reach.
  public func anchors(in room: DecorRoom = .home) -> [Occupancy.Point] {
    room.anchorPieces.compactMap { anchorSpots(in: room)[$0] }
  }

  /// Whether she can still walk up to every anchor piece that stands.
  public func reachesAnchors(in room: DecorRoom = .home) -> Bool {
    let spots = anchorSpots(in: room)
    return room.anchorPieces.allSatisfy { placement(of: $0) == nil || spots[$0] != nil }
  }

  /// Whether she can still walk from her bed to where she stands for the visit `name`; false while its
  /// piece is stored.
  public func canVisit(_ name: String, in room: DecorRoom = .home) -> Bool {
    guard let follow = room.visitFollows[name], let stop = point(of: follow) else { return false }
    let here = occupancy(in: room)
    // She walks round what is in the way, so the visit is open while a way to the stop is.
    let furniture = DecorLayout(placements: placements.filter(\.isBase), stored: stored)
    let spot = furniture.occupancy(in: room).nearestFree(to: stop) ?? stop
    // A stop a piece stands on is only as good as the nearest floor beside it.
    guard hypot(spot.x - stop.x, spot.z - stop.z) <= 0.15 else { return false }
    return here.connects(from: spawn(in: room), to: [spot])
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

  /// The box a piece of `item` fills on the floor turned by `eighthTurns`: the sides swap on a quarter turn,
  /// and at 45 degrees it is the box round the turned footprint, so a fit is never overstated.
  public static func footprint(of item: DecorItem, eighthTurns: Int) -> (
    width: Double, depth: Double
  ) {
    guard eighthTurns % 2 == 0 else {
      let side = (item.width + item.depth) / 2 * 0.5.squareRoot()
      return (side * 2, side * 2)
    }
    return eighthTurns % 4 == 0 ? (item.width, item.depth) : (item.depth, item.width)
  }

  /// On a wall the span runs along its x, whichever wall it is.
  static func span(of placement: Placement, item: DecorItem) -> Span? {
    switch placement.surface {
    case .floor:
      let (width, depth) = Self.footprint(of: item, eighthTurns: placement.eighthTurns)
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
    if let base = item.base {
      let home = Placement(item: itemID, surface: .floor, u: base.u, v: base.v, space: room.space)
      return accepts(home, in: room) ? home : nearestFit(to: home, in: room)
    }
    let candidates: [Placement]
    switch item.mount {
    case .floor:
      let preferred = room.floorSpots.map {
        Placement(item: itemID, surface: .floor, u: $0.u, v: $0.v, space: room.space)
      }
      let sweep = (-9...9).flatMap { v in
        (-9...9).map { u in
          Placement(item: itemID, surface: .floor, u: u, v: v, space: room.space)
        }
      }
      candidates = preferred + sweep
    case .wall:
      candidates = [Placement.Surface.backWall, .leftWall].flatMap { surface in
        (-9...9).map { Placement(item: itemID, surface: surface, u: $0, space: room.space) }
      }
    }
    return candidates.first { accepts($0, in: room) }
  }

  /// Puts every owned piece the layout has never met into the room, where it fits, else in the closet.
  public func settled(owned: Set<String>, in room: DecorRoom = .home) -> DecorLayout {
    var next = self
    // A new piece goes into the living room; the bedroom's closet is filled by hand.
    guard room.space == .living else { return self }
    for item in DecorItem.placeable(among: owned, in: room.space)
    where !item.isBase && !next.isPlaced(item.id) && !next.stored.contains(item.id) {
      if next.placements.filter({ !(DecorItem.item(shopID: $0.item)?.isBase ?? false) }).count
        < Self.maxPlaced,
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
  public func replacing(placements spots: [Placement], stowed: Set<String>? = nil) -> DecorLayout {
    var next = self
    next.placements = spots
    next.stored.subtract(spots.map(\.item))
    if let stowed {
      let own = Set(DecorItem.baseItems.map(\.id))
      next.stored = next.stored.subtracting(own).union(stowed.intersection(own))
    }
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

  /// The pieces of the room's own furniture put away, as the server keeps them.
  public var stowed: Set<String> {
    stored.filter { DecorItem.item(shopID: $0)?.isBase == true }
  }

  /// Whether `item` can be put away: a room keeps at least one bed or sofa for her.
  public func canStore(_ item: String) -> Bool {
    guard DecorItem.item(shopID: item)?.isRest == true else { return true }
    let space = placement(of: item)?.space ?? DecorItem.item(shopID: item)?.base?.space ?? .living
    return allPlacements.contains {
      $0.item != item && $0.space == space && DecorItem.item(shopID: $0.item)?.isRest == true
    }
  }

  public func storing(_ item: String) -> DecorLayout {
    var next = self
    next.placements.removeAll { $0.item == item }
    next.stored.insert(item)
    return next
  }

  /// Owned pieces not standing in the room, the ones put away first, then the shop's order.
  public func closet(owned: Set<String>, in room: DecorRoom = .home) -> [DecorItem] {
    let waiting = DecorItem.placeable(among: owned, in: room.space).filter { !isPlaced($0.id) }
    return waiting.filter { stored.contains($0.id) } + waiting.filter { !stored.contains($0.id) }
  }

  public func closetCount(owned: Set<String>, in room: DecorRoom = .home) -> Int {
    closet(owned: owned, in: room).count
  }

  /// Owned pieces standing in the room.
  public func placedCount(owned: Set<String>) -> Int {
    placements.filter { owned.contains($0.item) }.count
  }

  /// Without a placement of something no longer owned, such as a gift taken back.
  public func keeping(owned: Set<String>) -> DecorLayout {
    var next = self
    next.placements.removeAll {
      !owned.contains($0.item) && DecorItem.item(shopID: $0.item)?.isBase != true
    }
    return next
  }
}

extension Placement {
  fileprivate var isBase: Bool { DecorItem.item(shopID: item)?.isBase == true }
}
