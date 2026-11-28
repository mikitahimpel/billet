import Foundation

/// Which floor cells the cat cannot walk through, from the room's own furniture and the pieces
/// placed in it. One lookup per cell, built once for a layout and never per frame. A flat piece (a
/// rug) is not here: she walks over it.
public struct Occupancy: Equatable, Sendable {
  public typealias Point = (x: Double, z: Double)

  /// Cells run from `-reach` to `reach`, so 19 across at 5 cm.
  public static let reach = 9
  static let side = 2 * reach + 1
  /// How far past a piece's edge she keeps, so she does not brush it.
  static let clearance = 0.04
  /// From the middle of her to her side, in metres: a floor stop nearer a piece than this has her standing in it.
  public static let shoulder = 0.045
  /// How far her nose is ahead of where she stands, in metres: nearer than this to a piece she faces, her head is
  /// in it.
  public static let noseReach = 0.12
  /// The longest walk, in metres, taken straight across a piece's margin: out of a stop beside a piece, or into one.
  static let marginStep = 3.2 * DecorGrid.step
  /// How many times dearer a step into a piece's margin is than one over open floor, so a way keeps to the open
  /// floor wherever there is one.
  static let marginCost = 4.0

  private var blocked: [Bool]
  /// Share of the floor the pieces themselves leave open, without the margin she keeps.
  public let bareShare: Double
  /// The cells a piece itself covers, without the margin she keeps.
  private let covered: [Bool]
  /// The pieces themselves.
  private let spans: [Span]

  init(spans: [Span]) {
    self.spans = spans
    blocked = Array(repeating: false, count: Self.side * Self.side)
    var covered = Array(repeating: false, count: Self.side * Self.side)
    for span in spans {
      for v in -Self.reach...Self.reach {
        for u in -Self.reach...Self.reach
        where abs(DecorGrid.metres(u) - span.x) < span.halfX
          && abs(DecorGrid.metres(v) - span.z) < span.halfZ
        {
          covered[Self.index(u, v)] = true
        }
      }

      for v in -Self.reach...Self.reach {
        for u in -Self.reach...Self.reach {
          let dx = abs(DecorGrid.metres(u) - span.x)
          let dz = abs(DecorGrid.metres(v) - span.z)
          if dx < span.halfX + Self.clearance && dz < span.halfZ + Self.clearance {
            blocked[Self.index(u, v)] = true
          }
        }
      }
    }
    bareShare = Double(covered.filter { !$0 }.count) / Double(covered.count)
    self.covered = covered
  }

  public static func == (a: Occupancy, b: Occupancy) -> Bool { a.blocked == b.blocked }

  private static func index(_ u: Int, _ v: Int) -> Int { (v + reach) * side + (u + reach) }

  private static func inside(_ u: Int, _ v: Int) -> Bool { abs(u) <= reach && abs(v) <= reach }

  public func isBlocked(u: Int, v: Int) -> Bool {
    !Self.inside(u, v) || blocked[Self.index(u, v)]
  }

  /// Whether a piece itself stands on `point`, as against its margin.
  public func isSolid(at point: Point) -> Bool {
    let u = DecorGrid.cell(point.x)
    let v = DecorGrid.cell(point.z)
    return !Self.inside(u, v) || covered[Self.index(u, v)]
  }

  public func isBlocked(at point: Point) -> Bool {
    isBlocked(u: DecorGrid.cell(point.x), v: DecorGrid.cell(point.z))
  }

  /// Share of the floor cells she can stand on.
  public var freeShare: Double {
    Double(blocked.filter { !$0 }.count) / Double(blocked.count)
  }

  /// The cells reachable from `start` by 4-neighbour steps.
  func reachable(from start: (u: Int, v: Int)) -> Set<Int> {
    guard !isBlocked(u: start.u, v: start.v) else { return [] }
    var seen: Set<Int> = [Self.index(start.u, start.v)]
    var stack = [start]
    while let (u, v) = stack.popLast() {
      for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nu = u + du
        let nv = v + dv
        guard !isBlocked(u: nu, v: nv), seen.insert(Self.index(nu, nv)).inserted else { continue }
        stack.append((nu, nv))
      }
    }
    return seen
  }

  /// Whether she can walk from `start` to every one of `targets`.
  public func connects(from start: Point, to targets: [Point]) -> Bool {
    let from = nearestFree(to: start) ?? start
    let here = (u: DecorGrid.cell(from.x), v: DecorGrid.cell(from.z))
    let open = reachable(from: here)
    return targets.allSatisfy {
      open.contains(Self.index(DecorGrid.cell($0.x), DecorGrid.cell($0.z)))
    }
  }

  /// The nearest free cell to `point`, or itself when it is free.
  public func nearestFree(to point: Point) -> Point? {
    let u0 = DecorGrid.cell(point.x)
    let v0 = DecorGrid.cell(point.z)
    for ring in 0...(2 * Self.reach) {
      var best: (u: Int, v: Int)?
      var bestDistance = Double.infinity
      for v in (v0 - ring)...(v0 + ring) {
        for u in (u0 - ring)...(u0 + ring) where max(abs(u - u0), abs(v - v0)) == ring {
          guard !isBlocked(u: u, v: v) else { continue }
          let d = Double((u - u0) * (u - u0) + (v - v0) * (v - v0))
          if d < bestDistance {
            best = (u, v)
            bestDistance = d
          }
        }
      }
      if let best { return (DecorGrid.metres(best.u), DecorGrid.metres(best.v)) }
    }
    return nil
  }

  /// The way from `from` to `to` as corners to walk to, around what is blocked; nil when there is none.
  /// An empty list is a straight walk. Meant to be asked when she sets off, not every frame.
  ///
  /// No leg of it passes through a piece. It keeps the margin too wherever the floor lets it: a stop beside a piece
  /// lies in that piece's margin, so the way out of one and into one crosses the margin, by the shortest way to
  /// open floor.
  public func route(from: Point, to: Point) -> [Point]? {
    if clear(from: from, to: to) { return [] }
    guard let start = openCell(by: from), let goal = openCell(by: to),
      let cells = search(from: start, to: goal)
    else { return nil }
    var corners: [Point] = []
    var anchor = from
    var index = 0
    while index < cells.count {
      var next = index
      for ahead in index..<cells.count
      where walkable(from: anchor, to: cells[ahead]) { next = ahead }
      let corner = cells[next]
      if next == cells.count - 1 && walkable(from: anchor, to: to) { break }
      corners.append(corner)
      anchor = corner
      index = next + 1
    }
    return corners
  }

  /// Whether a straight walk passes through a piece itself, as against its margin. Touching its edge is not through.
  /// With `margin`, whether it passes within that many metres of one.
  public func crossesPiece(from a: Point, to b: Point, within margin: Double = 0) -> Bool {
    spans.contains { $0.isCrossed(from: a, to: b, margin: margin) }
  }

  /// Whether a straight line passes through a piece other than `own`.
  func crossesPiece(from a: Point, to b: Point, otherThan own: Span) -> Bool {
    spans.contains { $0 != own && $0.isCrossed(from: a, to: b) }
  }

  /// Metres from `point` to the nearest piece's edge; 0 on a piece.
  public func distanceToPiece(from point: Point) -> Double {
    spans.map { span in
      hypot(max(abs(point.x - span.x) - span.halfX, 0), max(abs(point.z - span.z) - span.halfZ, 0))
    }.min() ?? .infinity
  }

  /// A straight walk she may take: over open floor, or a short one across a margin that an end of it lies in.
  private func walkable(from a: Point, to b: Point) -> Bool {
    if clear(from: a, to: b) { return true }
    guard isBlocked(at: a) || isBlocked(at: b) else { return false }
    return hypot(b.x - a.x, b.z - a.z) <= Self.marginStep && !crossesPiece(from: a, to: b)
  }

  private func isCovered(u: Int, v: Int) -> Bool { !Self.inside(u, v) || covered[Self.index(u, v)] }

  /// Whether she fits in a cell of a piece's margin: the piece nearest it and the next nearest, a wall counted as
  /// one, leave her width between them. Beside one piece she brushes it; between two too close she is in both.
  private func hasRoom(u: Int, v: Int) -> Bool {
    let x = DecorGrid.metres(u)
    let z = DecorGrid.metres(v)
    let wall = 0.5
    var nearest = [wall - abs(x), wall - abs(z)]
    nearest += spans.map { span in
      hypot(max(abs(x - span.x) - span.halfX, 0), max(abs(z - span.z) - span.halfZ, 0))
    }
    nearest.sort()
    return nearest[0] + nearest[1] >= 2 * Self.shoulder
  }

  /// The cell a way to or from `point` starts in: its own while no piece covers that and the step to its middle
  /// crosses none, else the nearest such. From on a piece every step off it is through it, and the way starts on
  /// the open floor nearest.
  private func openCell(by point: Point) -> (Int, Int)? {
    if distanceToPiece(from: point) == 0 {
      return nearestFree(to: point).map { (DecorGrid.cell($0.x), DecorGrid.cell($0.z)) }
    }
    let u0 = DecorGrid.cell(point.x)
    let v0 = DecorGrid.cell(point.z)
    for ring in 0...(2 * Self.reach) {
      var best: (u: Int, v: Int)?
      var bestDistance = Double.infinity
      for v in (v0 - ring)...(v0 + ring) {
        for u in (u0 - ring)...(u0 + ring) where max(abs(u - u0), abs(v - v0)) == ring {
          let middle = (DecorGrid.metres(u), DecorGrid.metres(v))
          guard !isCovered(u: u, v: v), !crossesPiece(from: point, to: middle) else { continue }
          let d = hypot(middle.0 - point.x, middle.1 - point.z)
          if d < bestDistance {
            best = (u, v)
            bestDistance = d
          }
        }
      }
      if let best { return best }
    }
    return nil
  }

  /// Whether a straight walk crosses no blocked cell.
  public func clear(from a: Point, to b: Point) -> Bool {
    let length = hypot(b.x - a.x, b.z - a.z)
    let steps = max(1, Int(length / (DecorGrid.step / 2)))
    for step in 0...steps {
      let t = Double(step) / Double(steps)
      if isBlocked(at: (a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t)) { return false }
    }
    return true
  }

  private func search(from start: (Int, Int), to goal: (Int, Int)) -> [Point]? {
    struct Node {
      var cost: Double
      var guess: Double
      var u: Int
      var v: Int
    }
    func guess(_ u: Int, _ v: Int) -> Double { hypot(Double(u - goal.0), Double(v - goal.1)) }
    var best: [Int: Double] = [Self.index(start.0, start.1): 0]
    var parent: [Int: Int] = [:]
    var open = [Node(cost: 0, guess: guess(start.0, start.1), u: start.0, v: start.1)]
    while !open.isEmpty {
      let at = open.indices.min { open[$0].cost + open[$0].guess < open[$1].cost + open[$1].guess }!
      let node = open.remove(at: at)
      if (node.u, node.v) == goal {
        var path: [Point] = []
        var key = Self.index(node.u, node.v)
        while true {
          path.append(
            (
              DecorGrid.metres(key % Self.side - Self.reach),
              DecorGrid.metres(key / Self.side - Self.reach)
            ))
          guard let up = parent[key] else { break }
          key = up
        }
        return path.reversed()
      }
      for du in -1...1 {
        for dv in -1...1 where (du, dv) != (0, 0) {
          let nu = node.u + du
          let nv = node.v + dv
          guard !isCovered(u: nu, v: nv) else { continue }
          let inMargin = isBlocked(u: nu, v: nv)
          if inMargin, (nu, nv) != goal, !hasRoom(u: nu, v: nv) { continue }
          if inMargin || isBlocked(u: node.u, v: node.v) {
            let here = (DecorGrid.metres(node.u), DecorGrid.metres(node.v))
            let there = (DecorGrid.metres(nu), DecorGrid.metres(nv))
            if crossesPiece(from: here, to: there) { continue }
          } else if du != 0 && dv != 0
            && (isBlocked(u: node.u + du, v: node.v) || isBlocked(u: node.u, v: node.v + dv))
          {
            continue
          }
          let step = du != 0 && dv != 0 ? 1.4142 : 1
          let cost = node.cost + (inMargin ? Self.marginCost * step : step)
          let key = Self.index(nu, nv)
          guard cost < (best[key] ?? .infinity) else { continue }
          best[key] = cost
          parent[key] = Self.index(node.u, node.v)
          open.append(Node(cost: cost, guess: guess(nu, nv), u: nu, v: nv))
        }
      }
    }
    return nil
  }
}
