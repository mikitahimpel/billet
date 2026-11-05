import Foundation
import simd

/// A piece's footprint on a surface: a rectangle turned about its centre. On the floor, `x` and
/// `y` are the scene's `x` and `z`; on a wall they are along the wall and up it.
struct DecorBox: Equatable, Sendable {
  var centre: SIMD2<Float>
  /// Half the footprint's width and depth before it is turned.
  var half: SIMD2<Float>
  /// The turn about the vertical, in radians.
  var yaw: Float = 0

  /// The footprint's corners, turned.
  var corners: [SIMD2<Float>] {
    let across = Self.axes(yaw).0 * half.x
    let along = Self.axes(yaw).1 * half.y
    return [
      centre - across - along, centre + across - along, centre + across + along,
      centre - across + along,
    ]
  }

  /// Half the size of the upright rectangle the turned footprint fits in.
  var reach: SIMD2<Float> {
    let axes = Self.axes(yaw)
    return abs(axes.0) * half.x + abs(axes.1) * half.y
  }

  /// Whether the two footprints share any area. Footprints that only touch along an edge do not.
  func overlaps(_ other: DecorBox, tolerance: Float = 0.001) -> Bool {
    let mine = Self.axes(yaw)
    let theirs = Self.axes(other.yaw)
    let offset = other.centre - centre
    for axis in [mine.0, mine.1, theirs.0, theirs.1] {
      let reachMine = abs(simd_dot(mine.0, axis)) * half.x + abs(simd_dot(mine.1, axis)) * half.y
      let reachTheirs =
        abs(simd_dot(theirs.0, axis)) * other.half.x + abs(simd_dot(theirs.1, axis)) * other.half.y
      if abs(simd_dot(offset, axis)) >= reachMine + reachTheirs - tolerance { return false }
    }
    return true
  }

  /// The footprint's own axes on the surface, turned by `yaw` the way the scene turns a holder
  /// about its vertical.
  static func axes(_ yaw: Float) -> (SIMD2<Float>, SIMD2<Float>) {
    (SIMD2(cos(yaw), -sin(yaw)), SIMD2(sin(yaw), cos(yaw)))
  }
}

/// Where pieces may stand on one surface of a room. Pieces snap to a grid and to steps of turn,
/// keep inside the surface, and never overlap each other or anything fixed. Flat pieces, such as
/// rugs, lie under everything and only keep inside.
struct DecorPlan: Equatable, Sendable {
  enum Fit: Equatable, Sendable {
    case free
    /// Some of it would be outside the surface.
    case outside
    /// It would overlap the piece or the fixed thing named.
    case blocked(String)

    var isFree: Bool { self == .free }
  }

  var minimum: SIMD2<Float>
  var maximum: SIMD2<Float>
  /// The grid pieces snap to.
  var grid: Float
  /// The step turns snap to.
  var turnStep: Float = .pi / 12
  /// What never moves, by name.
  var fixed: [String: DecorBox] = [:]
  /// Each movable piece where it stands now.
  var pieces: [String: DecorBox] = [:]
  /// Pieces that lie flat and so overlap anything.
  var flat: Set<String> = []
  /// Pieces that only slide along the surface's width, keeping their depth and turn, such as a
  /// throw whose end hangs over the seat's front edge.
  var slidesOnly: Set<String> = []

  /// `point` on the nearest grid line crossing.
  func snapped(_ point: SIMD2<Float>) -> SIMD2<Float> {
    (point / grid).rounded(.toNearestOrAwayFromZero) * grid
  }

  /// `yaw` to the nearest step, between -π and π.
  func snapped(yaw: Float) -> Float {
    let turned = (yaw / turnStep).rounded() * turnStep
    return atan2(sin(turned), cos(turned))
  }

  /// Whether `box` can stand there for the piece `name`, which never blocks itself.
  func fit(_ box: DecorBox, for name: String?) -> Fit {
    let reach = box.reach
    let tolerance: Float = 0.0005
    guard all(box.centre - reach .>= minimum - tolerance),
      all(box.centre + reach .<= maximum + tolerance)
    else { return .outside }
    if let name, flat.contains(name) { return .free }
    for (other, area) in fixed.sorted(by: { $0.key < $1.key }) where area.overlaps(box) {
      return .blocked(other)
    }
    for (other, area) in pieces.sorted(by: { $0.key < $1.key })
    where other != name && !flat.contains(other) && area.overlaps(box) {
      return .blocked(other)
    }
    return .free
  }

  /// Where the piece `name` goes for a finger at `point` and a turn of `yaw`: snapped to the grid
  /// and the turn steps, and slid back inside the surface, so a piece pushed into a wall rides
  /// along it. Says whether it can stand there.
  func candidate(for name: String, at point: SIMD2<Float>, yaw: Float) -> (box: DecorBox, fit: Fit)?
  {
    guard var box = pieces[name] else { return nil }
    if slidesOnly.contains(name) {
      let depth = box.centre.y
      box.centre = inside(SIMD2(snapped(point).x, depth), reach: box.reach)
      box.centre.y = depth
    } else {
      box.yaw = snapped(yaw: yaw)
      box.centre = inside(snapped(point), reach: box.reach)
    }
    return (box, fit(box, for: name))
  }

  /// `centre` moved the least way that keeps something of `reach` inside the surface, on the grid
  /// where the grid allows.
  func inside(_ centre: SIMD2<Float>, reach: SIMD2<Float>) -> SIMD2<Float> {
    let low = minimum + reach
    let high = simd_max(maximum - reach, low)
    var point = simd_clamp(centre, low, high)
    for axis in 0..<2 where point[axis] != centre[axis] {
      // Off the grid against a wall: step back onto it if that still keeps inside.
      let onGrid = (point[axis] / grid).rounded(point[axis] > centre[axis] ? .up : .down) * grid
      if onGrid >= low[axis], onGrid <= high[axis] { point[axis] = onGrid }
    }
    return point
  }

  /// The free spot nearest `point` for a new piece of `half` size, searching outwards over the
  /// grid, or `nil` when there is no room.
  func openSpot(half: SIMD2<Float>, near point: SIMD2<Float>, yaw: Float = 0) -> SIMD2<Float>? {
    let reach = DecorBox(centre: .zero, half: half, yaw: yaw).reach
    let low = minimum + reach
    let high = maximum - reach
    guard all(low .<= high) else { return nil }
    var spots: [SIMD2<Float>] = []
    var x = (low.x / grid).rounded(.up) * grid
    while x <= high.x + 0.0001 {
      var y = (low.y / grid).rounded(.up) * grid
      while y <= high.y + 0.0001 {
        spots.append(SIMD2(x, y))
        y += grid
      }
      x += grid
    }
    return
      spots
      .filter { fit(DecorBox(centre: $0, half: half, yaw: yaw), for: nil).isFree }
      .min { simd_distance_squared($0, point) < simd_distance_squared($1, point) }
  }
}

/// The steps that can be undone, most recent last. Holding a fixed number keeps it small.
struct DecorHistory<Step> {
  private(set) var steps: [Step] = []
  var limit = 30

  var canUndo: Bool { !steps.isEmpty }

  mutating func record(_ step: Step) {
    steps.append(step)
    if steps.count > limit { steps.removeFirst(steps.count - limit) }
  }

  mutating func undo() -> Step? { steps.popLast() }

  mutating func clear() { steps.removeAll() }
}
