import Pet
import simd

/// Something soft built into a piece that the cat must not walk into, such as a pillow leaning on
/// the window or a folded throw: its footprint and height in the piece's own room units, from the
/// piece's near corner on the floor, as the piece is built.
struct GenzSoftPart: Hashable, Sendable {
  var min: SIMD2<Float>
  var max: SIMD2<Float>
  var bottom: Float
  var top: Float
}

extension GenzPiece.Kind {
  /// A pillow or throw on the seat: the cat lies beside it rather than keeping well clear.
  var isSoftSeatThing: Bool { isPillow || self == .blanket }

  /// The soft parts the cat goes round on this piece's top. Each is a little larger than the
  /// part as built, for the turn some of them are given and their stuffed bulge.
  var softParts: [GenzSoftPart] {
    func part(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ z0: Float, _ z1: Float)
      -> GenzSoftPart
    {
      GenzSoftPart(min: [x0, y0], max: [x1, y1], bottom: z0, top: z1)
    }
    switch self {
    case .quiltedDaybed:
      return [
        part(0.25, 1.7, 0, 0.85, 0.78, 1.32), part(1.7, 3.0, 0, 0.85, 0.78, 1.32),
        part(2.95, 4.05, 0, 0.85, 0.78, 1.32),
      ]
    case .daybed:
      return [part(0.25, 1.65, 0.55, 1.1, 0.78, 1.36), part(1.75, 3.15, 0.55, 1.1, 0.78, 1.31)]
    default:
      return []
    }
  }
}

/// Something on the cat's top that its body must not pass through, as a footprint on the floor
/// plane (scene x and z) and the height of its top.
struct GenzCatObstacle: Equatable, Sendable {
  var box: DecorBox
  var top: Float
  /// Whether the cat may get up onto it and sit or lie on its top, as on the cardigan.
  var sitOnTop = false
  /// Whether it is built into the piece the cat is on, as a pillow is, rather than standing on it.
  var builtIn = false
}

/// The cat's body seen from above: a capsule along its heading, in shares of its length, from the
/// tip of its nose to its rump and as wide as the widest cat's middle (the fluffy and Idol cats,
/// about half their length across). The tail is left out: it curls over what it touches.
enum GenzCatBody {
  /// From the middle of the body to where the round end begins, along the heading.
  static let reach: Float = 0.4
  static let radius: Float = 0.25
  /// How much further, in room units, the spots the cat is sent to and the ways it walks keep
  /// off things, so a body sampled anywhere between two checks stays clear too.
  static let pad: Float = 0.02

  /// Points along the body's middle line, from tail to nose, for testing against footprints.
  static func spine(at centre: SIMD2<Float>, heading: Float, length: Float) -> [SIMD2<Float>] {
    let forward = SIMD2(-sin(heading), -cos(heading))
    return (-3...3).map { centre + forward * (Float($0) / 3 * reach * length) }
  }
}

extension DecorBox {
  /// How far `point` is from the footprint, 0 inside it.
  func distance(to point: SIMD2<Float>) -> Float {
    let axes = Self.axes(yaw)
    let offset = point - centre
    let along = SIMD2(abs(simd_dot(offset, axes.0)), abs(simd_dot(offset, axes.1)))
    return simd_length(simd_max(along - half, .zero))
  }
}

extension GenzLayout {
  /// What stands on the cat's top or is built into it and stands above it: the pieces on it (a
  /// cardigan, mugs) and the soft parts of the piece itself (pillows, a folded throw).
  var catObstacles: [GenzCatObstacle] {
    guard let surface = catSurface else { return [] }
    let ground = cat.spot.z
    var out: [GenzCatObstacle] = []
    for placement in pieces {
      let size = placement.piece.kind.size
      let centre = SIMD2(placement.centre.x, placement.centre.y)
      if abs(placement.centre.z - ground) < 0.15, size.z >= 0.1,
        centre == simd_clamp(centre, surface.min, surface.max)
      {
        // A generated prop's box is its model's bounds; a round one fills less of it.
        let share = placement.piece.kind.idol?.footprint ?? 1
        out.append(
          GenzCatObstacle(
            box: DecorBox(
              centre: centre, half: [size.x / 2, size.y / 2] * share, yaw: placement.yaw),
            top: placement.centre.z + size.z, sitOnTop: placement.piece.kind.catSitsOnTop,
            builtIn: placement.piece.kind.isSoftSeatThing))
      }
      let axes = DecorBox.axes(placement.yaw)
      for part in placement.piece.kind.softParts {
        let bottom = placement.centre.z + part.bottom
        let top = placement.centre.z + part.top
        guard top > ground + 0.05, bottom < ground + cat.length * 0.6 else { continue }
        let local = (part.min + part.max) / 2 - SIMD2(size.x, size.y) / 2
        let box = DecorBox(
          centre: centre + axes.0 * local.x + axes.1 * local.y, half: (part.max - part.min) / 2,
          yaw: placement.yaw)
        let reach = box.reach
        guard box.centre.x + reach.x > surface.min.x, box.centre.x - reach.x < surface.max.x,
          box.centre.y + reach.y > surface.min.y, box.centre.y - reach.y < surface.max.y
        else { continue }
        out.append(GenzCatObstacle(box: box, top: top, builtIn: true))
      }
    }
    return out
  }

  /// Whether the cat's body, centred at `point` and facing `heading`, keeps off everything on its
  /// top, except what it is up on: anything no higher than `height` above the top, as the
  /// cardigan is for a cat lying on it.
  ///
  /// `ground` is the height of the level it stands on, the cat's own top unless said. `shape` is
  /// its body for the pose it is in, measured for the cat shown (``catBody``); without one, a
  /// capsule as wide as the slimmer cats standing.
  func catBodyIsClear(
    at point: SIMD2<Float>, heading: Float, height: Float = 0, ground: Float? = nil,
    obstacles: [GenzCatObstacle]? = nil, shape: GenzCatShape? = nil, pad: Float = 0
  ) -> Bool {
    let radius = cat.length * (shape?.radius ?? GenzCatBody.radius) + pad
    let spine =
      shape?.spine(at: point, heading: heading, length: cat.length)
      ?? GenzCatBody.spine(at: point, heading: heading, length: cat.length)
    let feet = (ground ?? cat.spot.z) + height
    for obstacle in obstacles ?? catObstacles where feet < obstacle.top - 0.06 {
      if spine.contains(where: { obstacle.box.distance(to: $0) < radius }) { return false }
    }
    return true
  }

  /// The headings tried for a cat that must turn to fit: every 15 degrees. The body is the same
  /// from either end, so half a turn covers them all.
  static let turns = (0..<12).map { Float($0) * .pi / 12 }

  /// A heading at `point` the cat can stand in without its body in anything: `want`, or the
  /// nearest of every 15 degrees that keeps clear. Nil when none does.
  func catClearHeading(
    at point: SIMD2<Float>, want: Float, height: Float? = nil,
    obstacles: [GenzCatObstacle]? = nil
  ) -> Float? {
    let obstacles = obstacles ?? catObstacles
    let height = height ?? catStandHeight(at: point, obstacles: obstacles)
    func clear(_ heading: Float) -> Bool {
      catBodyIsClear(
        at: point, heading: heading, height: height, obstacles: obstacles, pad: GenzCatBody.pad)
    }
    if clear(want) { return want }
    func off(_ heading: Float) -> Float {
      let turn = abs(remainder(heading - want, .pi))
      return min(turn, .pi - turn)
    }
    return Self.turns.sorted { off($0) < off($1) }.first(where: clear).map { turn in
      // Facing the end of the body nearer the way it wanted to face.
      abs(remainder(turn - want, 2 * .pi)) <= .pi / 2 ? turn : turn + .pi
    }
  }

  /// `want`, or the nearest heading at `point` the cat's body fits in.
  func catHeading(at point: SIMD2<Float>, want: Float, height: Float? = nil) -> Float {
    catClearHeading(at: point, want: want, height: height) ?? want
  }

  /// How high above its top the cat stands at `point`: up on something it may lie on, such as the
  /// cardigan, as soon as its body is over it, so it never stands in it, else on the top itself.
  func catStandHeight(at point: SIMD2<Float>, obstacles: [GenzCatObstacle]? = nil) -> Float {
    let over = cat.length * (GenzCatBody.reach + GenzCatBody.radius)
    let up = (obstacles ?? catObstacles).filter { $0.sitOnTop && $0.box.distance(to: point) < over }
      .map { $0.top - cat.spot.z }.max()
    // Sunk a little into the knit, which gives under the cat.
    return up.map { max($0 - 0.05, 0) } ?? 0
  }

  /// Where on top of `obstacle`, such as the cardigan, the cat lies: as near its middle as the
  /// cat's body keeps off the pillows beside it, or its middle when nowhere on it does.
  func catSpotOnTop(of obstacle: GenzCatObstacle) -> SIMD2<Float> {
    let axes = DecorBox.axes(obstacle.box.yaw)
    let obstacles = catObstacles
    var best: SIMD2<Float>?
    for x in stride(from: -obstacle.box.half.x, through: obstacle.box.half.x, by: 0.05) {
      for y in stride(from: -obstacle.box.half.y, through: obstacle.box.half.y, by: 0.05) {
        let at = obstacle.box.centre + axes.0 * x + axes.1 * y
        guard
          best.map({
            simd_distance(at, obstacle.box.centre)
              < simd_distance($0, obstacle.box.centre)
          }) ?? true,
          catClearHeading(at: at, want: 0, obstacles: obstacles) != nil
        else { continue }
        best = at
      }
    }
    return best ?? obstacle.box.centre
  }

  /// Waypoints from `start` to `goal` on the cat's top that keep its body, facing the way it
  /// walks, off everything standing there: a search over a grid a few centimetres across, then
  /// straightened where a straight walk is clear. What the cat may lie on, such as the cardigan,
  /// it walks over. A goal it cannot get to, say past mugs that fill the seat's width, it walks
  /// as near to as it can. Empty when the cat is there already or can get no nearer; just `goal`
  /// when the way is clear.
  func catRoute(from start: SIMD2<Float>, to goal: SIMD2<Float>) -> [SIMD2<Float>] {
    catRoute(from: start, to: goal, on: GenzCatLevel.homeID)
  }

  /// ``catRoute(from:to:)`` on `level`: the cat's own top, the floor or another piece's top,
  /// keeping the walking body (``catBody``) clear of what stands there.
  func catRoute(from start: SIMD2<Float>, to goal: SIMD2<Float>, on level: Int) -> [SIMD2<Float>] {
    guard simd_distance(start, goal) > 1e-4 else { return [] }
    let isHome = level == GenzCatLevel.homeID || (level == catHomeLevel && catSurface == nil)
    let blocking = (isHome ? catObstacles : catObstacles(on: level)).filter { !$0.sitOnTop }
    let ground = isHome ? cat.spot.z : catLevel(level)?.top ?? 0
    let surface: (min: SIMD2<Float>, max: SIMD2<Float>)
    if isHome, let home = catSurface {
      surface = home
    } else if let box = catLevel(level)?.box {
      surface = (box.centre - box.reach, box.centre + box.reach)
    } else {
      return [goal]
    }
    guard !blocking.isEmpty else { return [goal] }
    // Walking, the body is its standing one; on its own top, where it has always walked between
    // the pillows, the slimmer capsule it is checked with there.
    let shape: GenzCatShape? = isHome ? nil : catBody.standing
    func clear(_ from: SIMD2<Float>, _ to: SIMD2<Float>) -> Bool {
      let gap = to - from
      let heading = atan2(-gap.x, -gap.y)
      let steps = max(Int((simd_length(gap) / 0.04).rounded(.up)), 1)
      return (0...steps).allSatisfy {
        catBodyIsClear(
          at: from + gap * (Float($0) / Float(steps)), heading: heading, ground: ground,
          obstacles: blocking, shape: shape, pad: GenzCatBody.pad)
      }
    }
    if clear(start, goal) { return [goal] }

    // The floor is large: a coarser grid keeps the search quick.
    let cell: Float = isHome ? 0.08 : 0.12
    let low = simd_min(surface.min, simd_min(start, goal))
    let high = simd_max(surface.max, simd_max(start, goal))
    let columns = Int(((high.x - low.x) / cell).rounded(.up)) + 1
    let rows = Int(((high.y - low.y) / cell).rounded(.up)) + 1
    func point(_ index: Int) -> SIMD2<Float> {
      low + SIMD2(Float(index % columns), Float(index / columns)) * cell
    }
    func index(_ p: SIMD2<Float>) -> Int {
      let c = min(max(Int(((p.x - low.x) / cell).rounded()), 0), columns - 1)
      let r = min(max(Int(((p.y - low.y) / cell).rounded()), 0), rows - 1)
      return r * columns + c
    }
    // A cell is open when the body fits there facing along whatever is beside it.
    let margin = cat.length * (shape?.radius ?? GenzCatBody.radius)
    let open = (0..<(columns * rows)).map { i in
      !blocking.contains { $0.box.distance(to: point(i)) < margin }
    }
    let startIndex = index(start)
    // A body already in something (a cat set down there) walks straight out of it.
    let stuck = !Self.turns.contains { heading in
      catBodyIsClear(
        at: start, heading: heading, ground: ground, obstacles: blocking, shape: shape,
        pad: GenzCatBody.pad)
    }

    // A* over each cell's eight neighbours, each move checked with the body along it, until a
    // cell from which the cat walks straight to the goal.
    var cost = [Float](repeating: .infinity, count: open.count)
    var from = [Int](repeating: -1, count: open.count)
    var done = [Bool](repeating: false, count: open.count)
    cost[startIndex] = 0
    var frontier = GenzCellHeap()
    frontier.push(startIndex, 0)
    var reached: Int?
    var nearest = (index: startIndex, distance: simd_distance(start, goal))
    let moves = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)]
    while let current = frontier.pop() {
      guard !done[current] else { continue }
      done[current] = true
      let leaving = current == startIndex ? start : point(current)
      let distance = simd_distance(leaving, goal)
      if distance < cat.length * 0.5, current != startIndex, clear(leaving, goal) {
        reached = current
        break
      }
      if distance < nearest.distance { nearest = (current, distance) }
      let c = current % columns
      let r = current / columns
      for (dc, dr) in moves {
        let nc = c + dc
        let nr = r + dr
        guard nc >= 0, nc < columns, nr >= 0, nr < rows else { continue }
        let next = nr * columns + nc
        guard !done[next], open[next] else { continue }
        let total = cost[current] + cell * (dc != 0 && dr != 0 ? 1.4142 : 1)
        guard total < cost[next] else { continue }
        guard (current == startIndex && stuck) || clear(leaving, point(next)) else { continue }
        cost[next] = total
        from[next] = current
        frontier.push(next, total + simd_distance(point(next), goal))
      }
    }
    let end = reached ?? nearest.index
    guard end != startIndex else { return [] }
    var cells = [end]
    while let last = cells.last, from[last] >= 0 { cells.append(from[last]) }
    let path = cells.reversed().dropFirst().map(point) + (reached == nil ? [] : [goal])
    // Straightened: from each point, on to the furthest later one a straight walk reaches.
    var straight: [SIMD2<Float>] = []
    var at = start
    var i = 0
    while i < path.count {
      var furthest = i
      for j in stride(from: path.count - 1, to: i, by: -1) where clear(at, path[j]) {
        furthest = j
        break
      }
      straight.append(path[furthest])
      at = path[furthest]
      i = furthest + 1
    }
    return straight
  }
}

/// The cells a route search has still to look at, cheapest guess first.
private struct GenzCellHeap {
  private var items: [(cell: Int, guess: Float)] = []

  mutating func push(_ cell: Int, _ guess: Float) {
    items.append((cell, guess))
    var child = items.count - 1
    while child > 0 {
      let parent = (child - 1) / 2
      guard items[child].guess < items[parent].guess else { break }
      items.swapAt(child, parent)
      child = parent
    }
  }

  mutating func pop() -> Int? {
    guard let first = items.first else { return nil }
    let last = items.removeLast()
    if !items.isEmpty {
      items[0] = last
      var parent = 0
      while true {
        let left = parent * 2 + 1
        let right = left + 1
        var least = parent
        if left < items.count, items[left].guess < items[least].guess { least = left }
        if right < items.count, items[right].guess < items[least].guess { least = right }
        guard least != parent else { break }
        items.swapAt(parent, least)
        parent = least
      }
    }
    return first.cell
  }
}
