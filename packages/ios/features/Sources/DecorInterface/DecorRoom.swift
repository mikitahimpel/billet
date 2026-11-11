/// What a room already has in it that a piece cannot stand on, in metres.
public struct DecorRoom: Equatable, Sendable {
  let blocked: [Span]
  let backWallBlocked: [Span]
  let leftWallBlocked: [Span]
  /// Where a new floor piece goes first, in grid cells.
  public let floorSpots: [(u: Int, v: Int)]
  /// Where she steps down from her bed, and the floor spots she must always be able to reach: the way
  /// to the cat tree. A piece may not cut her off from them.
  public let spawn: Occupancy.Point
  public let anchors: [Occupancy.Point]
  /// Where she stands to visit the ball, the yarn basket and the window seat. A piece that cuts one off
  /// only takes that visit away; it does not stop her being placed.
  public let visits: [String: Occupancy.Point]
  /// The straight walks her routes are made of, which a piece may not stand across: bed to the tree.
  public let legs: [(from: Occupancy.Point, to: Occupancy.Point)]
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

  public static func == (a: DecorRoom, b: DecorRoom) -> Bool {
    a.blocked == b.blocked && a.backWallBlocked == b.backWallBlocked
      && a.leftWallBlocked == b.leftWallBlocked
  }

  /// Mochi's room as `Tools/make_room.py` builds it: the window seat, the nightstand, the corner plant,
  /// the stool with its lamp, the cat tree, the bowls' mat, her bed and the yarn basket on the floor;
  /// on the walls the shelf, the polaroid garland, the round window and the paw picture. The rug is
  /// flat and is not here.
  public static let home = DecorRoom(
    blocked: [
      Span(x: -0.41, z: 0, halfX: 0.095, halfZ: 0.21),
      Span(x: -0.39, z: 0.33, halfX: 0.105, halfZ: 0.115),
      Span(x: -0.4, z: -0.4, halfX: 0.06, halfZ: 0.06),
      Span(x: -0.1, z: -0.42, halfX: 0.062, halfZ: 0.062),
      Span(x: 0.36, z: -0.36, halfX: 0.1, halfZ: 0.1),
      Span(x: 0.107, z: -0.37, halfX: 0.1, halfZ: 0.045),
      Span(x: 0.06, z: -0.04, halfX: 0.19, halfZ: 0.19),
      Span(x: 0.37, z: 0.36, halfX: 0.08, halfZ: 0.08),
      Span(x: 0.2, z: 0.4, halfX: 0.06, halfZ: 0.05),
    ],
    backWallBlocked: [
      Span(x: 0.04, z: 0, halfX: 0.1, halfZ: 0.01),
      Span(x: -0.28, z: 0, halfX: 0.2, halfZ: 0.01),
    ],
    leftWallBlocked: [
      Span(x: 0.02, z: 0, halfX: 0.2, halfZ: 0.01),
      Span(x: 0.36, z: 0, halfX: 0.08, halfZ: 0.01),
    ],
    floorSpots: [(0, 7), (-3, 7), (4, 5), (-5, -2), (7, 0)],
    spawn: (0.0, 0.19),
    anchors: [(0.3, -0.12)],
    visits: ["ball": (-0.1, 0.26), "basket": (0.27, 0.26), "sill": (-0.24, 0.04)],
    legs: [((0.0, 0.19), (0.2, 0.2)), ((0.2, 0.2), (0.3, -0.12))])
}
