/// A floor point that follows a piece of the room's own furniture: where the cat goes in relation to it. While
/// the piece is stored there is no such point.
public struct DecorFollow: Equatable, Sendable {
  public let piece: String
  /// Metres from the piece's middle with no turn; a piece turned a quarter swings it round.
  public let dx: Double
  public let dz: Double

  public init(piece: String, dx: Double, dz: Double) {
    self.piece = piece
    self.dx = dx
    self.dz = dz
  }
}

/// What a room has in it that no piece can be put away from, in metres, and where the cat goes. The room's
/// furniture is not here: it is a piece like any other, in `DecorItem.baseItems`.
public struct DecorRoom: Equatable, Sendable {
  let blocked: [Span]
  let backWallBlocked: [Span]
  let leftWallBlocked: [Span]
  /// Where a new floor piece goes first, in grid cells.
  public let floorSpots: [(u: Int, v: Int)]
  /// Where she steps down from her bed when it is stored, or the room has none.
  public let spawn: Occupancy.Point
  /// Where she steps down from her bed while it stands.
  public let spawnFollow: DecorFollow
  /// The pieces she must always be able to walk up to, from her bed: the cat tree. A piece may not cut her
  /// off from them. A stored piece asks nothing.
  public let anchorPieces: [String]
  /// Where she stands to visit the ball, the yarn basket and the window seat. A piece that cuts one off
  /// only takes that visit away; it does not stop her being placed.
  public let visitFollows: [String: DecorFollow]
  /// The least share of the floor she must keep.
  public let minimumFree = 0.35

  func blockedWall(_ surface: Placement.Surface) -> [Span] {
    switch surface {
    case .floor: []
    case .backWall: backWallBlocked
    case .leftWall: leftWallBlocked
    }
  }

  /// The cat's floor with the room's own fixtures and `solid` pieces blocked.
  func occupancy(solid: [Span]) -> Occupancy { Occupancy(spans: blocked + solid) }

  public static func == (a: DecorRoom, b: DecorRoom) -> Bool {
    a.blocked == b.blocked && a.backWallBlocked == b.backWallBlocked
      && a.leftWallBlocked == b.leftWallBlocked && a.anchorPieces == b.anchorPieces
      && a.visitFollows == b.visitFollows && a.spawnFollow == b.spawnFollow
  }

  /// Mochi's room as `Tools/make_room.py` builds it. Its floor furniture is in the catalog; what stays here
  /// is the walls' own: the shelf, the polaroid garland, the round window and the paw picture.
  public static let home = DecorRoom(
    blocked: [],
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
    spawnFollow: DecorFollow(piece: "base-donutbed", dx: -0.05, dz: 0.24),
    anchorPieces: ["base-cattree"],
    visitFollows: [
      "ball": DecorFollow(piece: "base-rug", dx: -0.1, dz: 0.21),
      "basket": DecorFollow(piece: "base-basket", dx: -0.08, dz: -0.09),
      "sill": DecorFollow(piece: "base-windowseat", dx: 0.16, dz: 0.04),
    ])
}
