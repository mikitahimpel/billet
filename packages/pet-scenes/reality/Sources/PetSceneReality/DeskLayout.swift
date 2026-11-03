import Foundation
import simd

/// Where everything stands at the desk, in room units (``GenzRoomPoint``): a desk against the wall
/// with paper in the middle, and a cork board above it. The room is narrow and tall, because a
/// phone held upright shows it that way.
enum DeskLayout {
  static let width: Float = 6
  static let height: Float = 10.5
  static let wall: Float = 0.3

  static let desk = (x0: Float(0.3), x1: Float(5.7), y0: Float(0.35), y1: Float(3.6))
  static let deskTop: Float = 2.6
  static let board = (x0: Float(0.75), x1: Float(5.25), z0: Float(4.4), z1: Float(9.4))
  /// How far the cork stands out from the wall, which is where the notes are pinned.
  static let boardFront: Float = 0.16

  /// The blank paper to draw on: its middle on the desk, size across and deep, and its turn.
  static let paper = (
    centre: GenzRoomPoint(3.0, 2.3, 2.6), width: Float(3.1), depth: Float(2.1),
    yaw: Float(0.06)
  )
  static let lamp = (base: GenzRoomPoint(0.85, 1.0, 2.6), shade: GenzRoomPoint(2.05, 1.85, 4.0))
  /// Where the cat sits when it visits, the way it faces, and its length.
  static let cat = (spot: GenzRoomPoint(5.1, 1.9, 2.6), heading: Float(0.35), length: Float(1.2))

  /// The paper's corners on the desk, far left first and round to near left, as the view sees
  /// a page: its top edge is the one away from you.
  static var paperCorners: [GenzRoomPoint] {
    let spec = paper
    let (cosine, sine) = (cos(spec.yaw), sin(spec.yaw))
    return [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { (u: Float, v: Float) in
      let across = u * spec.width / 2
      let toward = v * spec.depth / 2
      // Turning by `yaw` about up, in room axes: x along the wall, y toward the viewer.
      return GenzRoomPoint(
        spec.centre.x + across * cosine + toward * sine,
        spec.centre.y - across * sine + toward * cosine, spec.centre.z + 0.04)
    }
  }

  static let camera = GenzCamera.Home(
    target: GenzRoomPoint(3.0, 2.0, 5.1).scene, yaw: 0.1, pitch: 0.34, distance: 18,
    fieldOfView: 40, yawLimits: -0.12...0.32, pitchLimits: 0.2...0.55)

  /// The latest note, pinned large in the top left of the board.
  static let large = (centre: SIMD2<Float>(2.05, 7.9), side: Float(2.2))
  /// The other notes' places, newest first: beside the large one, then two rows under it.
  static let small: [SIMD2<Float>] = [
    [4.3, 8.6], [4.3, 7.35],
    [1.45, 6.0], [2.8, 6.05], [4.15, 6.0],
    [1.45, 4.95], [2.8, 4.9], [4.15, 4.95],
  ]
  static let smallSide: Float = 1.0

  /// How many notes the board shows. The rest are in the list.
  static var capacity: Int { 1 + small.count }

  /// One note on the board.
  struct Pin: Equatable {
    var id: UUID
    /// The middle of the note, on the face of the cork.
    var centre: GenzRoomPoint
    var side: Float
    /// Its lean on the board, in radians, from its id so it stays put as notes arrive.
    var tilt: Float
    /// Which pin colour holds it, from its id.
    var pin: Int
  }

  static let pinColours: [UInt32] = [0xE5503A, 0xFFD166, 0x3DDC84, 0x7FB2FF]

  /// The board's notes for `ids`, newest first: the first large, the next ones small, and none
  /// past what the board holds.
  static func pins(for ids: [UUID]) -> [Pin] {
    ids.prefix(capacity).enumerated().map { index, id in
      let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
      let lean = (Float(bytes[0] % 9) - 4) / 4 * 0.07
      let spot = index == 0 ? large.centre : small[index - 1]
      return Pin(
        id: id, centre: GenzRoomPoint(spot.x, boardFront, spot.y),
        side: index == 0 ? large.side : smallSide, tilt: lean,
        pin: Int(bytes[1]) % pinColours.count)
    }
  }
}
