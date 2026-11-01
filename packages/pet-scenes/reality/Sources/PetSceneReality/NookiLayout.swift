import DesignSystem
import Foundation
import simd

/// The paints on offer, all from the shared palette.
enum NookiSwatch: String, Codable, CaseIterable, Sendable {
  case cream
  case sunlight
  case terracotta
  case clay
  case cocoa
  case moss

  var swatch: Swatch {
    switch self {
    case .cream: Palette.paperTurned
    case .sunlight: Palette.lightWarm
    case .terracotta: Palette.clayLit
    case .clay: Palette.clay
    case .cocoa: Palette.clayDeep
    case .moss: Palette.greenLit
    }
  }

  var name: String {
    switch self {
    case .cream: "Cream"
    case .sunlight: "Sunlight"
    case .terracotta: "Terracotta"
    case .clay: "Clay"
    case .cocoa: "Cocoa"
    case .moss: "Moss"
    }
  }

  var rgb: SIMD3<Float> {
    SIMD3(Float(swatch.red), Float(swatch.green), Float(swatch.blue)) / 255
  }
}

/// How a pair's room has been changed from the original. Everything left out is as it was, which
/// keeps this small enough to send as a frame.
struct NookiLayout: Codable, Equatable, Sendable {
  struct Cell: Codable, Hashable, Sendable {
    var column: Int
    var row: Int
  }

  var wall: NookiSwatch?
  var floor: NookiSwatch?
  /// Where each moved piece stands, by model name.
  var pieces: [String: Cell] = [:]
}

/// Where furniture may stand. Pieces snap to a grid, stay in the room and never overlap each other
/// or anything fixed.
struct NookiFloorPlan {
  struct Area: Equatable {
    var centre: SIMD2<Float>
    var half: SIMD2<Float>

    func overlaps(_ other: Area) -> Bool {
      all(abs(centre - other.centre) .< half + other.half)
    }
  }

  static let cellSize: Float = 0.1
  static let floorMin = SIMD2<Float>(-0.58, -0.58)
  static let floorMax = SIMD2<Float>(0.68, 0.68)

  /// Each movable piece where it first stood.
  var homes: [String: Area] = [:]
  /// What never moves.
  var fixed: [Area] = []

  static func nearestCell(to point: SIMD2<Float>) -> NookiLayout.Cell {
    NookiLayout.Cell(
      column: Int((point.x / cellSize).rounded()), row: Int((point.y / cellSize).rounded()))
  }

  static func centre(of cell: NookiLayout.Cell) -> SIMD2<Float> {
    SIMD2(Float(cell.column), Float(cell.row)) * cellSize
  }

  /// Where `name` stands in `layout`.
  func area(of name: String, in layout: NookiLayout) -> Area? {
    guard var area = homes[name] else { return nil }
    if let cell = layout.pieces[name] { area.centre = Self.centre(of: cell) }
    return area
  }

  /// The cell nearest `point` if `name` can stand there.
  func cell(for name: String, nearest point: SIMD2<Float>, in layout: NookiLayout)
    -> NookiLayout.Cell?
  {
    guard var area = homes[name] else { return nil }
    let cell = Self.nearestCell(to: point)
    area.centre = Self.centre(of: cell)
    return fits(area, for: name, in: layout) ? cell : nil
  }

  private func fits(_ area: Area, for name: String, in layout: NookiLayout) -> Bool {
    guard all(area.centre - area.half .>= Self.floorMin),
      all(area.centre + area.half .<= Self.floorMax)
    else { return false }
    if fixed.contains(where: area.overlaps) { return false }
    return !homes.keys.contains { other in
      other != name && self.area(of: other, in: layout).map(area.overlaps) == true
    }
  }
}

/// The layout kept on this device.
struct NookiLayoutStore {
  private static let key = "nooki.layout"

  var defaults: UserDefaults

  /// The stored layout. One that can't be read gives way to the original room.
  func load() -> NookiLayout {
    defaults.data(forKey: Self.key)
      .flatMap { try? JSONDecoder().decode(NookiLayout.self, from: $0) } ?? NookiLayout()
  }

  func save(_ layout: NookiLayout) {
    defaults.set(try? JSONEncoder().encode(layout), forKey: Self.key)
  }
}

/// Where a point on screen falls on the floor.
enum NookiFloorRay {
  /// The floor point under `point`, or nil if that ray never reaches the floor. The field of view
  /// is the camera's vertical one.
  static func floorPoint(
    under point: SIMD2<Float>, viewSize: SIMD2<Float>, camera: SIMD3<Float>, target: SIMD3<Float>,
    verticalFieldOfView degrees: Float, height: Float = 0
  ) -> SIMD2<Float>? {
    let forward = simd_normalize(target - camera)
    let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
    let up = simd_cross(right, forward)
    let reach = tan(degrees * .pi / 360)
    let across = (point.x / viewSize.x * 2 - 1) * reach * viewSize.x / viewSize.y
    let down = (1 - point.y / viewSize.y * 2) * reach
    let ray = forward + right * across + up * down
    guard ray.y < 0 else { return nil }
    let landing = camera + ray * ((height - camera.y) / ray.y)
    return SIMD2(landing.x, landing.z)
  }
}
