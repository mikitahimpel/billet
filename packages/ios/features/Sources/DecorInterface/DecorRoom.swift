/// What a room already has in it that a piece cannot stand on, in metres.
public struct DecorRoom: Equatable, Sendable {
  let blocked: [Span]
  let backWallBlocked: [Span]
  let leftWallBlocked: [Span]
  /// Where a new floor piece goes first, in grid cells.
  public let floorSpots: [(u: Int, v: Int)]
  /// Where she starts, and the floor spots she walks to: her bed's front, the tree, the window seat,
  /// the ball and the yarn basket. A piece may not cut her off from any of them.
  public let spawn: Occupancy.Point
  public let anchors: [Occupancy.Point]
  /// The least share of the floor she must keep.
  public let minimumFree = 0.35

  func blockedWall(_ surface: Placement.Surface) -> [Span] {
    switch surface {
    case .floor: []
    case .backWall: backWallBlocked
    case .leftWall: leftWallBlocked
    }
  }

  /// The cat's floor with the room's own furniture and `solid` pieces blocked.
  func occupancy(solid: [Span]) -> Occupancy { Occupancy(spans: blocked + solid) }

  /// Her stops, each moved to the nearest cell the room itself leaves free: she sits beside a piece,
  /// and a cell beside it may fall inside its margin.
  var stops: [Occupancy.Point] {
    let bare = Occupancy(spans: blocked)
    return anchors.map { bare.nearestFree(to: $0) ?? $0 }
  }

  public static func == (a: DecorRoom, b: DecorRoom) -> Bool {
    a.blocked == b.blocked && a.backWallBlocked == b.backWallBlocked
      && a.leftWallBlocked == b.leftWallBlocked
  }

  /// Mochi's room as the scene builds it: her bed, the cat tree, the yarn basket, the window seat,
  /// the stool with its lamp, and the wall space the polaroid garland and the window take.
  public static let home = DecorRoom(
    blocked: [
      Span(x: 0.06, z: -0.04, halfX: 0.19, halfZ: 0.19),
      Span(x: 0.36, z: -0.36, halfX: 0.11, halfZ: 0.11),
      Span(x: 0.37, z: 0.36, halfX: 0.1, halfZ: 0.1),
      Span(x: -0.41, z: 0, halfX: 0.11, halfZ: 0.23),
      Span(x: -0.15, z: -0.34, halfX: 0.08, halfZ: 0.08),
    ],
    backWallBlocked: [Span(x: -0.28, z: 0, halfX: 0.2, halfZ: 0.01)],
    leftWallBlocked: [Span(x: 0, z: 0, halfX: 0.25, halfZ: 0.01)],
    floorSpots: [(-4, 6), (-6, 4), (-2, 8), (7, 0), (2, 7)],
    spawn: (0.0, 0.19),
    anchors: [(0.3, -0.12), (0.2, 0.2), (-0.1, 0.26), (0.27, 0.26), (-0.24, 0.04), (-0.12, 0.1)])
}
