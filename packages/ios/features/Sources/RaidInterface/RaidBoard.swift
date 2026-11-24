import Foundation

/// A place on the floor seen from above, in metres from the middle of the room.
public struct RaidPoint: Equatable, Hashable, Sendable, Codable {
  public var x: Double
  public var z: Double

  public init(x: Double, z: Double) {
    self.x = x
    self.z = z
  }

  public func distance(to other: RaidPoint) -> Double { hypot(other.x - x, other.z - z) }

  /// The point `share` of the way to `other`.
  public func toward(_ other: RaidPoint, share: Double) -> RaidPoint {
    RaidPoint(x: x + (other.x - x) * share, z: z + (other.z - z) * share)
  }

  /// The point `metres` on from here, away from `other`; straight back along x when they coincide.
  public func away(from other: RaidPoint, by metres: Double) -> RaidPoint {
    let d = distance(to: other)
    guard d > 1e-9 else { return RaidPoint(x: x + metres, z: z) }
    return RaidPoint(x: x + (x - other.x) / d * metres, z: z + (z - other.z) / d * metres)
  }
}

/// A piece of furniture as the raid sees it: a box on the floor with a top she can stand on.
public struct RaidPiece: Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let centre: RaidPoint
  public let halfX: Double
  public let halfZ: Double
  /// Metres.
  public let height: Double
  /// A rug: drawn, never in the way.
  public let isFlat: Bool

  public init(
    id: String, title: String, centre: RaidPoint, halfX: Double, halfZ: Double, height: Double,
    isFlat: Bool = false
  ) {
    self.id = id
    self.title = title
    self.centre = centre
    self.halfX = halfX
    self.halfZ = halfZ
    self.height = height
    self.isFlat = isFlat
  }

  /// She walks over it without a jump: bowls, a pile of books.
  public var isLow: Bool { isFlat || height < RaidRules.stepOver }

  public func contains(_ point: RaidPoint, margin: Double = 0) -> Bool {
    abs(point.x - centre.x) < halfX + margin && abs(point.z - centre.z) < halfZ + margin
  }
}

/// The pair's room as a level: its furniture and where she starts.
public struct RaidBoard: Equatable, Sendable {
  public let pieces: [RaidPiece]
  public let start: RaidPoint

  public init(pieces: [RaidPiece], start: RaidPoint) {
    self.pieces = pieces
    self.start = start
  }

  /// The piece whose top is at `point`, the highest when two overlap; nil on the bare floor.
  public func top(at point: RaidPoint) -> RaidPiece? {
    pieces.filter { !$0.isLow && $0.contains(point) }.max { $0.height < $1.height }
  }

  public func piece(_ id: String) -> RaidPiece? { pieces.first { $0.id == id } }

  public func clamped(_ point: RaidPoint) -> RaidPoint {
    let reach = RaidRules.reach - RaidRules.catRadius
    return RaidPoint(x: min(max(point.x, -reach), reach), z: min(max(point.z, -reach), reach))
  }
}
