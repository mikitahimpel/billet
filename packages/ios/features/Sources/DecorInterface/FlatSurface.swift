import Foundation

/// A flat piece lying on the floor (a rug): a rectangle turned about its center, with its top at `top` in the
/// room's space. Whatever rests on it, a laser dot or her paws, is at that height rather than the floor's.
public struct FlatSurface: Equatable, Sendable {
  public var x: Double
  public var z: Double
  /// Along the piece's own x and z, before it turns.
  public var halfWidth: Double
  public var halfDepth: Double
  /// Radians about the up axis, as the scene turns the piece.
  public var yaw: Double
  public var top: Double

  public init(
    x: Double, z: Double, halfWidth: Double, halfDepth: Double, yaw: Double, top: Double
  ) {
    self.x = x
    self.z = z
    self.halfWidth = halfWidth
    self.halfDepth = halfDepth
    self.yaw = yaw
    self.top = top
  }

  public func contains(x px: Double, z pz: Double) -> Bool {
    let dx = px - x
    let dz = pz - z
    let c = cos(yaw)
    let s = sin(yaw)
    return abs(c * dx - s * dz) <= halfWidth && abs(s * dx + c * dz) <= halfDepth
  }

  /// The height of what is under the point: the highest flat piece covering it, else `floor`.
  public static func height(
    atX x: Double, z: Double, floor: Double, over pieces: [FlatSurface]
  ) -> Double {
    pieces.reduce(floor) { highest, piece in
      piece.contains(x: x, z: z) ? max(highest, piece.top) : highest
    }
  }
}
