import Foundation
import Pet
import PetScene
import RealityKit

/// Where everything stands in the room, in room units (``GenzRoomPoint``). The numbers follow the
/// mockups in `docs/genz-rooms.md`, so the room and its drawing can be checked side by side.
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
  /// Whether the generated props stand in for the hand-made ones (``withIdolProps()``).
  var idolProps = false

  /// What tells one room from another: its furniture, and which props it shows.
  struct Key: Hashable {
    var furniture: RoomFurniture
    var idolProps = false
  }

  var key: Key { Key(furniture: furniture, idolProps: idolProps) }

  /// The room furnished with `furniture`, with the generated props for `idolProps`.
  static func of(_ furniture: RoomFurniture, idolProps: Bool = false) -> GenzLayout {
    let layout = windowSeat.furnished(furniture)
    return idolProps ? layout.withIdolProps() : layout
  }

  static func of(_ key: Key) -> GenzLayout { of(key.furniture, idolProps: key.idolProps) }

  /// How thick a window's sill is. The wall under the window stops at the sill's underside, so
  /// the two never show a top in the same plane.
  /// How far a window sill stops short of the wall's outer face, so seen from outside the wall the
  /// two never share a plane.
  private static let sillInset: Float = 0.02
  private static let windowSill: Float = 0.12

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
  /// on it, somewhere the cat's body fits: not in a corner between pillows too small for it.
  func onCatSurface(_ point: SIMD2<Float>) -> SIMD2<Float> {
    guard let surface = catSurface else { return point }
    let margin = SIMD2<Float>(repeating: cat.length * 0.35)
    let low = surface.min + margin
    let high = simd_max(surface.max - margin, low)
    let spot = clearOfClutter(simd_clamp(point, low, high), within: low, high)
    let obstacles = catObstacles
    func fits(_ at: SIMD2<Float>) -> Bool {
      catClearHeading(at: at, want: 0, obstacles: obstacles) != nil
    }
    guard !obstacles.isEmpty, !fits(spot) else { return spot }
    // Out from it a ring of 8 cm at a time, the nearest fit in the first ring with one.
    let step: Float = 0.08
    let rings = Int((simd_length(high - low) / step).rounded(.up))
    for ring in 1...max(rings, 1) {
      var best: SIMD2<Float>?
      for i in -ring...ring {
        for j in -ring...ring where abs(i) == ring || abs(j) == ring {
          let at = spot + SIMD2(Float(i), Float(j)) * step
          guard at == simd_clamp(at, low, high),
            best.map({ simd_distance(at, spot) < simd_distance($0, spot) }) ?? true, fits(at)
          else { continue }
          best = at
        }
      }
      if let best { return best }
    }
    return spot
  }
}
