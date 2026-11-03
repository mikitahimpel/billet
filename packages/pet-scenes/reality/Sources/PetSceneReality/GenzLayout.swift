import Foundation
import Pet
import PetScene
import RealityKit

/// Where everything stands in one styled room, in room units (``GenzRoomPoint``). The numbers
/// follow the mockups in `docs/genz-rooms.md`, so the room and its drawing can be checked side by
/// side.
@MainActor
struct GenzLayout {
  struct Placement {
    var piece: GenzPiece
    /// The middle of the piece's footprint, on the surface it stands on.
    var centre: GenzRoomPoint
    /// Turn about the vertical, in radians.
    var yaw: Float = 0
  }

  /// A flat rectangle in the room, such as the note's paper.
  struct Panel {
    var centre: GenzRoomPoint
    var width: Float
    var height: Float
    /// Turn about the vertical; 0 faces out of the back wall.
    var yaw: Float = 0

    /// The four corners, clockwise from top left as seen from the front.
    var corners: [GenzRoomPoint] {
      let across = SIMD2(cos(yaw), -sin(yaw)) * width / 2
      return [(-1, 1), (1, 1), (1, -1), (-1, -1)].map { side, up in
        GenzRoomPoint(
          centre.x + across.x * Float(side), centre.y + across.y * Float(side),
          centre.z + height / 2 * Float(up))
      }
    }
  }

  var style: RoomStyle
  var camera: GenzCamera.Home
  var pieces: [Placement]
  /// Where the cat sits, the way it faces and how long it is from nose to tail.
  var cat: (spot: GenzRoomPoint, heading: Float, length: Float)
  var note: Panel
  /// The paper's colour, under the drawing.
  var paper: GenzColour
  /// The LED strip as one path along the walls.
  var led: [GenzRoomPoint]
  var ledColour: GenzColour
  /// The hole the outside is seen through.
  var window: [GenzRoomPoint]
  /// The wall the sunset disc is projected on, or `nil` for a room without one.
  var discWall: Panel?
  /// Where the lamp's light starts, and the point it is aimed at.
  var lamp: (at: GenzRoomPoint, aim: GenzRoomPoint)
  var lampColour: GenzColour
  var shell: @MainActor (GenzKit) -> [Entity]
  /// The floor's width (x) and depth (y), from the back wall's left end.
  var floor: SIMD2<Float>
  /// The top the cat lives on, when it is not a piece's: the window sill in the first Window
  /// Seat, whose daybed is lower than the sill the cat sits on.
  var catTop: (min: SIMD2<Float>, max: SIMD2<Float>)? = nil
  /// The set of furniture in the room.
  var furniture = RoomFurniture.original

  /// What tells one room from another: its style and its furniture.
  struct Key: Hashable {
    var style: RoomStyle
    var furniture: RoomFurniture
  }

  var key: Key { Key(style: style, furniture: furniture) }

  static func of(_ style: RoomStyle, furniture: RoomFurniture = .original) -> GenzLayout? {
    switch style {
    case .nooki: nil
    case .sunsetLamp: sunsetLamp.furnished(furniture)
    case .windowSeat: windowSeat.furnished(furniture)
    }
  }

  static func of(_ key: Key) -> GenzLayout? { of(key.style, furniture: key.furniture) }

  /// How thick a window's sill is. The wall under the window stops at the sill's underside, so
  /// the two never show a top in the same plane.
  /// How far a window sill stops short of the wall's outer face, so seen from outside the wall the
  /// two never share a plane.
  private static let sillInset: Float = 0.02
  private static let windowSill: Float = 0.12

  // MARK: - Sunset Lamp

  private enum Sunset {
    static let width: Float = 8
    static let depth: Float = 9
    static let height: Float = 5.4
    static let wall: Float = 0.35
    static let window = (y0: Float(1.7), y1: Float(4.1), z0: Float(2.0), z1: Float(4.3))
    static let disc = GenzRoomPoint(3.1, 0, 3.05)
    static let lampCentre = GenzRoomPoint(0.68, 0.5, 1.02)
  }

  static let sunsetLamp: GenzLayout = {
    let (width, depth, height, wall, window) = (
      Sunset.width, Sunset.depth, Sunset.height, Sunset.wall, Sunset.window
    )
    let lampYaw = atan2(Sunset.lampCentre.x - Sunset.disc.x, Sunset.lampCentre.y - Sunset.disc.y)
    let ledHeight = height - 0.14
    return GenzLayout(
      style: .sunsetLamp,
      camera: GenzCamera.Home(
        target: GenzRoomPoint(3.0, 3.6, 1.0).scene, yaw: 0.6, pitch: 0.44, distance: 20,
        fieldOfView: 40, yawLimits: -0.2...1.6, pitchLimits: 0.22...0.85),
      pieces: [
        Placement(piece: GenzPiece(.checkeredRug), centre: GenzRoomPoint(3.9, 5.75, 0)),
        Placement(piece: GenzPiece(.cubeNightstand), centre: GenzRoomPoint(0.58, 0.58, 0)),
        Placement(
          piece: GenzPiece(.phoneOnCharger), centre: GenzRoomPoint(0.37, 0.75, 1.02), yaw: 0.3),
        Placement(piece: GenzPiece(.sunsetLamp), centre: Sunset.lampCentre, yaw: lampYaw),
        Placement(piece: GenzPiece(.platformBed), centre: GenzRoomPoint(3.6, 1.7, 0)),
        Placement(piece: GenzPiece(.sneakers), centre: GenzRoomPoint(2.95, 5.4, 0.03), yaw: -0.25),
        Placement(piece: GenzPiece(.hoodiePile), centre: GenzRoomPoint(1.3, 4.6, 0)),
        Placement(piece: GenzPiece(.monstera), centre: GenzRoomPoint(1.1, 6.6, 0)),
        Placement(
          piece: GenzPiece(.posterFrame), centre: GenzRoomPoint(0.03, 0.82, 2.6), yaw: .pi / 2),
      ],
      cat: (GenzRoomPoint(4.7, 2.45, 1.02), 3.3, 1.35),
      note: Panel(centre: GenzRoomPoint(3.1, 0.04, 3.14), width: 1.8, height: 1.98),
      paper: GenzColour(0xFFF3E6),
      led: [
        GenzRoomPoint(width, 0.03, ledHeight), GenzRoomPoint(0.03, 0.03, ledHeight),
        GenzRoomPoint(0.03, depth, ledHeight),
      ],
      ledColour: GenzColour(0xFFD9C8),
      window: [
        GenzRoomPoint(-wall, window.y0, window.z1), GenzRoomPoint(-wall, window.y1, window.z1),
        GenzRoomPoint(-wall, window.y1, window.z0), GenzRoomPoint(-wall, window.y0, window.z0),
      ],
      discWall: Panel(
        centre: GenzRoomPoint(width / 2, 0.02, height / 2), width: width, height: height),
      lamp: (GenzRoomPoint(0.68, 0.62, 1.62), Sunset.disc),
      lampColour: GenzColour(0xFF9A52),
      shell: sunsetShell,
      floor: [width, depth])
  }()

  private static func sunsetShell(_ kit: GenzKit) -> [Entity] {
    let (width, depth, height, wall, window) = (
      Sunset.width, Sunset.depth, Sunset.height, Sunset.wall, Sunset.window
    )
    let side = kit.matte(GenzColour(0x251E2C))
    let back = kit.matte(GenzColour(0x2E2433))
    let cut = kit.matte(GenzColour(0x4A3B4F))
    let opening = window.y1 - window.y0
    let sill = windowSill
    return [
      kit.block(
        -wall, -wall, -wall, width + wall, depth + wall, wall, kit.matte(GenzColour(0x3A2C2C))),
      kit.block(-wall, -wall, 0, width + wall, wall, height, back),
      kit.block(-wall, 0, 0, wall, window.y0, height, side),
      kit.block(-wall, window.y1, 0, wall, depth - window.y1, height, side),
      kit.block(-wall, window.y0, 0, wall, opening, window.z0 - sill, side),
      kit.block(-wall, window.y0, window.z1, wall, opening, height - window.z1, side),
      kit.block(
        -wall * 0.6, (window.y0 + window.y1) / 2 - 0.05, window.z0, 0.08, 0.1,
        window.z1 - window.z0, cut),
      kit.block(
        -wall + sillInset, window.y0 - 0.1, window.z0 - sill, wall - sillInset + 0.3,
        opening + 0.2, sill,
        kit.matte(GenzColour(0x5A4A58))),
      kit.block(-wall, -wall, height, width + wall, wall, 0.03, cut),
      kit.block(-wall, 0, height, wall, depth, 0.03, cut),
    ]
  }

  // MARK: - Window Seat

  enum Seat {
    static let width: Float = 7.6
    static let depth: Float = 6
    static let height: Float = 5.4
    static let wall: Float = 0.35
    static let window = (x0: Float(0.6), x1: Float(7.0), z0: Float(1.3), z1: Float(5.0))
    /// How far the sill under the window reaches into the room.
    static let sillDepth: Float = 0.57
  }

  static let windowSeat: GenzLayout = {
    let (wall, window) = (Seat.wall, Seat.window)
    let ledY: Float = 0.03
    return GenzLayout(
      style: .windowSeat,
      camera: GenzCamera.Home(
        target: GenzRoomPoint(4.3, 2.4, 1.9).scene, yaw: 0.34, pitch: 0.42, distance: 19.5,
        fieldOfView: 40, yawLimits: -0.3...1.6, pitchLimits: 0.18...0.8),
      pieces: [
        Placement(piece: GenzPiece(.roundRug), centre: GenzRoomPoint(4.9, 4.3, 0)),
        Placement(piece: GenzPiece(.daybed), centre: GenzRoomPoint(3.8, 1.22, 0)),
        Placement(piece: GenzPiece(.milkCrate), centre: GenzRoomPoint(2.15, 3.35, 0)),
        Placement(piece: GenzPiece(.bookStack), centre: GenzRoomPoint(2.15, 3.28, 0.75)),
        Placement(piece: GenzPiece(.thriftLamp), centre: GenzRoomPoint(2.15, 3.27, 0.97)),
        Placement(piece: GenzPiece(.snakePlant), centre: GenzRoomPoint(1.2, 0.28, 1.3)),
        Placement(
          piece: GenzPiece(.phoneOnCharger), centre: GenzRoomPoint(5.2, 0.27, 1.3), yaw: 0.1),
      ],
      cat: (GenzRoomPoint(6.2, 0.3, 1.3), 4.0, 1.25),
      note: Panel(centre: GenzRoomPoint(3.52, -0.13, 3.12), width: 1.72, height: 1.9),
      paper: GenzColour(0xF6F0E2),
      led: [
        GenzRoomPoint(window.x0 - 0.1, ledY, window.z0 + 0.02),
        GenzRoomPoint(window.x0 - 0.1, ledY, window.z1 + 0.1),
        GenzRoomPoint(window.x1 + 0.1, ledY, window.z1 + 0.1),
        GenzRoomPoint(window.x1 + 0.1, ledY, window.z0 + 0.02),
      ],
      ledColour: GenzColour(0xFFE2B0),
      window: [
        GenzRoomPoint(window.x0, -wall, window.z1), GenzRoomPoint(window.x1, -wall, window.z1),
        GenzRoomPoint(window.x1, -wall, window.z0), GenzRoomPoint(window.x0, -wall, window.z0),
      ],
      discWall: nil,
      lamp: (GenzRoomPoint(2.15, 3.27, 1.6), GenzRoomPoint(2.15, 3.27, 0)),
      lampColour: GenzColour(0xFFC36B),
      shell: windowShell,
      floor: [Seat.width, Seat.depth],
      catTop: ([window.x0 - 0.2, 0], [window.x1 + 0.2, Seat.sillDepth]))
  }()

  private static func windowShell(_ kit: GenzKit) -> [Entity] {
    let (width, depth, height, wall, window) = (
      Seat.width, Seat.depth, Seat.height, Seat.wall, Seat.window
    )
    let back = kit.matte(GenzColour(0x1A2436))
    let trim = kit.matte(GenzColour(0x2E3A50))
    let opening = window.x1 - window.x0
    let sill = windowSill
    var parts: [Entity] = [
      kit.block(
        -wall, -wall, -wall, width + wall, depth + wall, wall, kit.matte(GenzColour(0x2A2F3B))),
      kit.block(-wall, 0, 0, wall, depth, height, kit.matte(GenzColour(0x141D2C))),
      kit.block(-wall, -wall, 0, window.x0 + wall, wall, height, back),
      kit.block(window.x1, -wall, 0, width - window.x1, wall, height, back),
      kit.block(window.x0, -wall, 0, opening, wall, window.z0 - sill, back),
      kit.block(window.x0, -wall, window.z1, opening, wall, height - window.z1, back),
      kit.block(
        window.x0 - 0.2, -wall + sillInset, window.z0 - sill, opening + 0.4,
        Seat.sillDepth + wall - sillInset, sill,
        kit.matte(GenzColour(0x3A4660))),
      kit.block(-wall, -wall, height, width + wall, wall, 0.03, trim),
      kit.block(-wall, 0, height, wall, depth, 0.03, trim),
    ]
    for share in [Float(0.25), 0.75] {
      let x = window.x0 + opening * share
      parts.append(
        kit.block(x - 0.05, -wall * 0.75, window.z0, 0.1, 0.1, window.z1 - window.z0, trim))
    }
    let glass = kit.part(
      kit.plane(width: opening, height: window.z1 - window.z0),
      kit.glow(GenzColour(0x9FB7D9), opacity: 0.06),
      at: GenzRoomPoint((window.x0 + window.x1) / 2, -wall / 2, (window.z0 + window.z1) / 2).scene)
    parts.append(glass)
    return parts
  }
}

extension GenzLayout {
  /// The top of the piece the cat lives on, as its footprint on the floor plane (scene x and z),
  /// or nil when the cat is on the floor. Trips keep to it, so the cat never walks out over the
  /// floor at the height of the bed.
  var catSurface: (min: SIMD2<Float>, max: SIMD2<Float>)? {
    if let catTop { return catTop }
    let spot = cat.spot
    guard spot.z > 0.1 else { return nil }
    for placement in pieces {
      let size = placement.piece.kind.size
      let turned = abs(sin(placement.yaw)) > 0.5
      let half = SIMD2(turned ? size.y : size.x, turned ? size.x : size.y) / 2
      let centre = SIMD2(placement.centre.x, placement.centre.y)
      let offset = SIMD2(spot.x, spot.y) - centre
      guard abs(offset.x) <= half.x, abs(offset.y) <= half.y, size.z > spot.z * 0.5 else {
        continue
      }
      return (centre - half, centre + half)
    }
    return nil
  }

  /// `point` moved onto the cat's surface, a little in from its edges and clear of what stands
  /// on it.
  func onCatSurface(_ point: SIMD2<Float>) -> SIMD2<Float> {
    guard let surface = catSurface else { return point }
    let margin = SIMD2<Float>(repeating: cat.length * 0.35)
    let low = surface.min + margin
    let high = simd_max(surface.max - margin, low)
    return clearOfClutter(simd_clamp(point, low, high), within: low, high)
  }
}
