import Foundation
import Pet
import RealityKit
import simd

/// How high each of a cat's clips holds its lowest point (a paw, or the belly lying down, never
/// the tail) above the lowest point of its rest pose, which the room stands on the surface, over
/// the clip's time. In shares of the length the room scales the cat by; measured from the cat's
/// own mesh and clips by `scripts/measure_cat_ground.py` into `Cat_<model>.ground.json`.
struct CatGroundTable: Decodable, Sendable {
  /// Samples a second.
  var rate: Double
  /// How tall the rest pose is, in the same shares, to check the app loads the pose measured.
  var rest: Float?
  var clips: [String: [Float]]

  /// The table shipped beside `model`'s clips, or nil for a cat with none.
  static func of(_ model: CatModel) -> CatGroundTable? {
    guard
      let url = Bundle.module.url(
        forResource: "\(CatCatalog.resourceName(model)).ground", withExtension: "json",
        subdirectory: CatCatalog.folder),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }

  /// The lowest point's height in `action` `time` seconds in, between samples a straight line,
  /// a loop wrapping round and a one-shot clip held on its last sample. 0 for a clip not
  /// measured.
  func lift(_ action: CatAction, at time: Double, loops: Bool) -> Float {
    guard let samples = clips[action.rawValue], !samples.isEmpty else { return 0 }
    guard samples.count > 1 else { return samples[0] }
    let span = Double(samples.count - 1)
    var at = max(time, 0) * rate
    if loops { at = at.truncatingRemainder(dividingBy: span) } else { at = min(at, span) }
    let index = min(Int(at), samples.count - 2)
    let share = Float(at - Double(index))
    return samples[index] + (samples[index + 1] - samples[index]) * share
  }
}

/// The top of a piece the cat stands on, as built: for each cell of a grid over its footprint,
/// the height of the highest triangle over the cell's middle, in the piece holder's own space.
/// Built once from the piece's meshes, so it follows the piece wherever it is moved.
struct GenzHeightField: Sendable {
  var origin: SIMD2<Float>
  var cell: Float
  var columns: Int
  var rows: Int
  /// Row by row; -infinity where nothing is over the cell.
  var heights: [Float]

  /// The surface's height at `point` (holder space x and z), nil off it.
  func height(at point: SIMD2<Float>) -> Float? {
    let at = (point - origin) / cell
    let column = Int(at.x.rounded(.down))
    let row = Int(at.y.rounded(.down))
    guard column >= 0, row >= 0, column < columns, row < rows else { return nil }
    let height = heights[row * columns + column]
    guard height.isFinite else { return nil }
    // Between the middles of the four cells round it, a smooth blend, where they all have a top.
    let near = at - 0.5
    let c0 = Int(near.x.rounded(.down))
    let r0 = Int(near.y.rounded(.down))
    guard c0 >= 0, r0 >= 0, c0 + 1 < columns, r0 + 1 < rows else { return height }
    let corners = [
      heights[r0 * columns + c0], heights[r0 * columns + c0 + 1],
      heights[(r0 + 1) * columns + c0], heights[(r0 + 1) * columns + c0 + 1],
    ]
    guard corners.allSatisfy(\.isFinite) else { return height }
    let u = near.x - Float(c0)
    let v = near.y - Float(r0)
    let low = corners[0] + (corners[1] - corners[0]) * u
    let high = corners[2] + (corners[3] - corners[2]) * u
    return low + (high - low) * v
  }

  /// The heights of everything under `root` (its meshes in `root`'s space), on a grid `cell`
  /// across. Nil for a piece with no mesh.
  @MainActor
  static func of(_ root: Entity, cell: Float = 0.025) -> GenzHeightField? {
    var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
    SceneParts.visit(root) { entity in
      guard let model = entity as? ModelEntity, let mesh = model.model?.mesh, entity.isEnabled
      else { return }
      let transform = model.transformMatrix(relativeTo: root)
      for instance in mesh.contents.instances {
        let placed = transform * instance.transform
        guard let source = mesh.contents.models[instance.model] else { continue }
        for part in source.parts {
          let points = part.positions.elements.map { point in
            let moved = placed * SIMD4(point, 1)
            return SIMD3(moved.x, moved.y, moved.z)
          }
          guard let indices = part.triangleIndices?.elements else { continue }
          for start in stride(from: 0, to: indices.count - 2, by: 3) {
            triangles.append(
              (
                points[Int(indices[start])], points[Int(indices[start + 1])],
                points[Int(indices[start + 2])]
              ))
          }
        }
      }
    }
    guard !triangles.isEmpty else { return nil }
    var low = SIMD2<Float>(repeating: .infinity)
    var high = SIMD2<Float>(repeating: -.infinity)
    for (a, b, c) in triangles {
      for p in [a, b, c] {
        low = simd_min(low, SIMD2(p.x, p.z))
        high = simd_max(high, SIMD2(p.x, p.z))
      }
    }
    let columns = max(Int(((high.x - low.x) / cell).rounded(.up)), 1)
    let rows = max(Int(((high.y - low.y) / cell).rounded(.up)), 1)
    var heights = [Float](repeating: -.infinity, count: columns * rows)
    for (a, b, c) in triangles {
      let pa = SIMD2(a.x, a.z)
      let pb = SIMD2(b.x, b.z)
      let pc = SIMD2(c.x, c.z)
      let area = (pb.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (pb.y - pa.y)
      // Upright triangles (walls, sides) have no top to stand on; their edges are on the tops
      // beside them.
      guard abs(area) > 1e-8 else { continue }
      let from = simd_max(((simd_min(simd_min(pa, pb), pc) - low) / cell - 0.5).rounded(.up), .zero)
      let to = simd_min(
        ((simd_max(simd_max(pa, pb), pc) - low) / cell - 0.5).rounded(.down),
        SIMD2(Float(columns - 1), Float(rows - 1)))
      guard from.x <= to.x, from.y <= to.y else { continue }
      for row in Int(from.y)...Int(to.y) {
        for column in Int(from.x)...Int(to.x) {
          let p = low + (SIMD2(Float(column), Float(row)) + 0.5) * cell
          let u = ((pb.x - p.x) * (pc.y - p.y) - (pc.x - p.x) * (pb.y - p.y)) / area
          let v = ((pc.x - p.x) * (pa.y - p.y) - (pa.x - p.x) * (pc.y - p.y)) / area
          let w = 1 - u - v
          guard u >= -1e-4, v >= -1e-4, w >= -1e-4 else { continue }
          let y = a.y * u + b.y * v + c.y * w
          let index = row * columns + column
          if y > heights[index] { heights[index] = y }
        }
      }
    }
    return GenzHeightField(origin: low, cell: cell, columns: columns, rows: rows, heights: heights)
  }
}

/// A critically damped spring: eases a value to its goal without overshoot, so a step onto the
/// cardigan or a change of surface settles in a fraction of a second instead of popping.
struct GenzSpring: Sendable {
  var value: Float
  var velocity: Float = 0
  /// How stiff, per second: 18 settles most of the way in about a quarter of a second.
  var rate: Float = 18

  mutating func step(towards goal: Float, by time: Float) {
    guard time > 0 else { return }
    // The exact solution over the step, so a long frame never overshoots.
    let offset = value - goal
    let decay = exp(-rate * time)
    let next = (offset + (velocity + rate * offset) * time) * decay
    velocity = (velocity - rate * (velocity + rate * offset) * time) * decay
    value = goal + next
  }
}

/// What the room keeps for standing the cat on its surface: the clip table of the cat shown,
/// each walkable piece's measured top, the level the cat is on, and the springs easing it there.
struct CatFooting {
  var table: CatGroundTable?
  /// The model's place in its holder that stands its rest pose's lowest point on the holder.
  var base = SIMD3<Float>.zero
  /// Measured tops by piece index, for the pieces the cat stands on.
  var tops: [Int: GenzHeightField] = [:]
  /// The pieces among ``tops`` that lie on a level and raise the cat walking over them.
  var walkOver: [Int] = []
  /// The level the cat is on (``GenzCatLevel``).
  var level = GenzCatLevel.homeID
  var height: GenzSpring?
  /// The clip being faded out of: which, how far into it the fade began, its rate, and when.
  var fade: (action: CatAction, time: Double, rate: Float, start: Double)?
  var shown: CatAction?
  var shownStart = 0.0
  var shownRate: Float = 1
  /// What the footing has cost since it was last logged, in seconds: summed, the slowest frame,
  /// and the slowest way worked out (``GenzRoom/planWay(for:)``).
  var cost = (sum: 0.0, slowest: 0.0, frames: 0, plan: 0.0, since: 0.0)

  mutating func count(_ seconds: Double, at clock: Double) {
    cost.sum += seconds
    cost.slowest = max(cost.slowest, seconds)
    cost.frames += 1
    guard clock - cost.since > 5 else { return }
    NookiTrace.footingCost(
      average: cost.sum / Double(cost.frames), slowest: cost.slowest, frames: cost.frames,
      plan: cost.plan)
    cost = (0, 0, 0, 0, clock)
  }
}

/// Seconds on a monotonic clock, for timing the footing.
func footingNow() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

extension GenzRoom {
  /// Measures the tops of the pieces the cat can stand on, once they are built.
  func measureTops() {
    var tops: [Int: GenzHeightField] = [:]
    for (index, placement) in layout.pieces.enumerated()
    where pieceHolders.indices.contains(index)
      && (placement.piece.kind.catLevel != nil || placement.piece.kind.catWalksOver
        || placement.piece.kind.catSitsOnTop)
    {
      tops[index] = GenzHeightField.of(pieceHolders[index])
    }
    footing.tops = tops
    footing.walkOver = tops.keys.sorted().filter {
      layout.pieces[$0].piece.kind.catWalksOver || layout.pieces[$0].piece.kind.catSitsOnTop
    }
  }

  /// How high the surface under `point` is on `level`: the level's top as built where the cat's
  /// paws are, raised by anything it walks over there (a rug, the cardigan, a throw).
  func groundHeight(at point: SIMD2<Float>, on level: Int) -> Float {
    groundHeight(at: point, on: level, home: layout.homeLevelPiece)
  }

  /// ``groundHeight(at:on:)`` with the piece the cat's own top is on already found.
  private func groundHeight(at point: SIMD2<Float>, on level: Int, home: Int?) -> Float {
    let base: Float
    switch level {
    case GenzCatLevel.floorID: base = 0
    case GenzCatLevel.homeID:
      base = home.flatMap { top(of: $0, at: point) } ?? layout.cat.spot.scene.y
    default: base = top(of: level, at: point) ?? layout.catLevel(level)?.top ?? 0
    }
    var height = base
    for index in footing.walkOver {
      guard let over = top(of: index, at: point),
        over > base - 0.02, over < base + Self.walkOverRise
      else { continue }
      height = max(height, over)
    }
    return height
  }

  /// The most a thing lying on a level raises the cat walking over it: a rug, the cardigan.
  static let walkOverRise: Float = 0.3

  /// The measured top of piece `index` at `point` in the room, nil off it or before it is built.
  private func top(of index: Int, at point: SIMD2<Float>) -> Float? {
    guard let field = footing.tops[index], pieceHolders.indices.contains(index) else { return nil }
    let holder = pieceHolders[index]
    guard holder.isEnabled else { return nil }
    let local = holder.convert(position: SIMD3(point.x, 0, point.y), from: room)
    return field.height(at: SIMD2(local.x, local.z)).map { height in
      holder.convert(position: SIMD3(local.x, height, local.z), to: room).y
    }
  }

  /// Where the cat's paws are on the surface: under the middle of its body, and for a standing
  /// cat under its shoulders and hips too. In a dished bed, only the middle.
  func pawPoints(at point: SIMD2<Float>, heading: Float, base: CatBase) -> [SIMD2<Float>] {
    let inBed =
      layout.pieces.indices.contains(footing.level)
      && layout.pieces[footing.level].piece.kind.catLevel == .bed
    guard base == .stand, !inBed else { return [point] }
    let forward = SIMD2(-sin(heading), -cos(heading)) * layout.cat.length * 0.25
    return [point, point + forward, point - forward]
  }

  /// The surface's height under the cat now.
  func groundUnderCat(base: CatBase) -> Float {
    let home = layout.homeLevelPiece
    return pawPoints(at: catSpot, heading: bodyHeading, base: base)
      .map { groundHeight(at: $0, on: footing.level, home: home) }.max()
      ?? layout.cat.spot.scene.y
  }

  /// Stands the cat on what is under it, after the frame has put it where it is: its holder
  /// eased onto the surface by a spring, and the model raised or lowered so the lowest point of
  /// the clip's pose, faded the way the clips fade, touches it. Not while it is held, falling
  /// from a hand, or in the air in a jump.
  func stepFooting(_ step: Float, rate: Float) {
    guard let rig, let model = catModel else { return }
    let started = footingNow()
    defer { footing.count(footingNow() - started, at: clock) }
    if rig.current != footing.shown {
      if let shown = footing.shown {
        footing.fade = (
          shown, (clock - footing.shownStart) * Double(footing.shownRate), footing.shownRate, clock
        )
      }
      footing.shown = rig.current
      footing.shownStart = clock
    }
    if rate != footing.shownRate {
      // Kept in step with the clip's own time when its rate changes.
      let into = (clock - footing.shownStart) * Double(footing.shownRate)
      footing.shownRate = rate
      footing.shownStart = clock - into / Double(max(rate, 0.001))
    }
    let length = layout.cat.length
    var lift = clipLift(rig.current, since: footing.shownStart, rate: footing.shownRate)
    if let fade = footing.fade, let from = rig.info[fade.action] {
      let fadeLength =
        fade.action == .sleep || rig.current == .sleep ? CatRig.sleepBlend : CatRig.blend
      let into = Float((clock - fade.start) / fadeLength)
      if into >= 1 {
        footing.fade = nil
      } else {
        let time = fade.time + (clock - fade.start) * Double(fade.rate)
        let old = footing.table?.lift(fade.action, at: time, loops: from.loops) ?? 0
        lift = old + (lift - old) * into
      }
    }
    let airborne = toys.liftedAt != nil || dropped != nil || brainBody.jump != nil
    model.position = footing.base - [0, (airborne ? 0 : lift) * length, 0]
    guard !airborne else {
      footing.height = nil
      return
    }
    let base = rig.current.flatMap { rig.info[$0]?.base } ?? .sleep
    let goal = groundUnderCat(base: base)
    var spring = footing.height ?? GenzSpring(value: catHolder.position.y)
    if reduceMotion { spring = GenzSpring(value: goal) }
    spring.step(towards: goal, by: step)
    if abs(spring.value - goal) < 0.0005, abs(spring.velocity) < 0.01 {
      spring = GenzSpring(value: goal)
    }
    footing.height = spring
    catHolder.position.y = spring.value
  }

  /// The lowest point's lift in `action`, played at `rate` since `start`.
  private func clipLift(_ action: CatAction?, since start: Double, rate: Float) -> Float {
    guard let action, let info = rig?.info[action] else { return 0 }
    return footing.table?.lift(action, at: (clock - start) * Double(rate), loops: info.loops) ?? 0
  }
}
