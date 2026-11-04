import Foundation

/// Where a moved piece of a room's furniture stands: across the room, into it, and the way it
/// faces, in radians. Sent and stored as `[x, z, yaw]`.
public struct PieceSpot: Codable, Hashable, Sendable {
  public var x: Double
  public var z: Double
  public var yaw: Double

  public init(x: Double, z: Double, yaw: Double) {
    self.x = x
    self.z = z
    self.yaw = yaw
  }

  public init(from decoder: any Decoder) throws {
    var values = try decoder.unkeyedContainer()
    x = try values.decode(Double.self)
    z = try values.decode(Double.self)
    yaw = try values.decode(Double.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.unkeyedContainer()
    try values.encode(x)
    try values.encode(z)
    try values.encode(yaw)
  }
}

/// Where the furniture of one room stands, by piece. A piece missing from `spots` stands where
/// the room first put it, so an empty arrangement is the room as it came. Both partners' rooms
/// show the last arrangement either of them made, room by room.
public struct RoomArrangement: Codable, Hashable, Sendable {
  /// The room and furniture set, such as `windowSeat.cosyNook`.
  public var room: String
  public var spots: [String: PieceSpot]

  public init(room: String, spots: [String: PieceSpot]) {
    self.room = room
    self.spots = spots
  }
}
