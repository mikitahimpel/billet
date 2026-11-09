/// What the shop has put into the room, drawn by a scene and changed only by the shop's rules.
/// Positions are metres on the floor plane, the floor's top at height 0 and the walls along
/// x = -0.6 and z = -0.6. A wall piece uses the back wall, so its `z` is ignored.
public struct RoomLayout: Codable, Hashable, Sendable {
  public struct Placement: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let item: ShopItem.ID
    public var x: Double
    public var z: Double
    public var yaw: Double

    public init(id: String, item: ShopItem.ID, x: Double, z: Double, yaw: Double = 0) {
      self.id = id
      self.item = item
      self.x = x
      self.z = z
      self.yaw = yaw
    }
  }

  public private(set) var placements: [Placement]
  public private(set) var wall: ShopItem.ID?
  public private(set) var floor: ShopItem.ID?

  public init(placements: [Placement] = [], wall: ShopItem.ID? = nil, floor: ShopItem.ID? = nil) {
    self.placements = placements
    self.wall = wall
    self.floor = floor
  }

  public func material(on surface: RoomSurface) -> ShopItem.ID? {
    switch surface {
    case .wall: wall
    case .floor: floor
    }
  }

  /// Where the next piece goes when nothing says otherwise: the first open spot of a short list
  /// that keeps clear of the cat's bed, the bowl and the wall under the wire.
  static let floorSpots: [(x: Double, z: Double)] = [
    (-0.2, 0.2), (0.28, 0.28), (-0.2, -0.2), (0.3, -0.08), (-0.02, 0.5), (0.55, -0.15),
  ]
  static let wallSpots: [(x: Double, z: Double)] = [
    (0.0, -0.59), (0.25, -0.59), (-0.45, -0.59), (0.5, -0.59),
  ]

  func freeSpot(for mount: ShopItem.Mount) -> (x: Double, z: Double)? {
    let spots = mount == .wall ? Self.wallSpots : Self.floorSpots
    return spots.first { spot in
      !placements.contains { abs($0.x - spot.x) < 0.01 && abs($0.z - spot.z) < 0.01 }
    }
  }

  mutating func add(_ placement: Placement) {
    placements.append(placement)
  }

  mutating func remove(_ id: Placement.ID) throws(ShopError) -> Placement {
    guard let index = placements.firstIndex(where: { $0.id == id }) else {
      throw .unknownPlacement
    }
    return placements.remove(at: index)
  }

  mutating func move(_ id: Placement.ID, x: Double, z: Double, yaw: Double) throws(ShopError) {
    guard let index = placements.firstIndex(where: { $0.id == id }) else {
      throw .unknownPlacement
    }
    placements[index].x = x
    placements[index].z = z
    placements[index].yaw = yaw
  }

  mutating func paint(_ surface: RoomSurface, with id: ShopItem.ID?) {
    switch surface {
    case .wall: wall = id
    case .floor: floor = id
    }
  }
}
