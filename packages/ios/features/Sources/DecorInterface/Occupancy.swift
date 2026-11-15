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

  private var blocked: [Bool]
  /// Share of the floor the pieces themselves leave open, without the margin she keeps.
  public let bareShare: Double
  /// The cells a piece itself covers, without the margin she keeps.
  private let covered: [Bool]

  init(spans: [Span]) {
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
  public func route(from: Point, to: Point) -> [Point]? {
    guard
      let start = nearestFree(to: from).map({ (DecorGrid.cell($0.x), DecorGrid.cell($0.z)) }),
      let goal = nearestFree(to: to).map({ (DecorGrid.cell($0.x), DecorGrid.cell($0.z)) })
    else { return nil }
    if clear(from: from, to: to) { return [] }
    guard let cells = search(from: start, to: goal) else { return nil }
    var corners: [Point] = []
    var anchor = from
    var index = 0
    while index < cells.count {
      var next = index
      for ahead in index..<cells.count
      where clear(from: anchor, to: cells[ahead]) { next = ahead }
      let corner = cells[next]
      if next == cells.count - 1 && clear(from: anchor, to: to) { break }
      corners.append(corner)
      anchor = corner
      index = next + 1
    }
    return corners
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
          guard !isBlocked(u: nu, v: nv) else { continue }
          if du != 0 && dv != 0
            && (isBlocked(u: node.u + du, v: node.v) || isBlocked(u: node.u, v: node.v + dv))
          {
            continue
          }
          let cost = node.cost + (du != 0 && dv != 0 ? 1.4142 : 1)
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
