import Pet
import simd

extension GenzLayout {
  /// What stands on the top the cat lives on and the cat goes round, such as a cardigan or mugs
  /// on the window seat: each footprint widened by most of half the cat's length, so the cat's
  /// head stops short of it too. Flat things, such as a phone, are walked over.
  var catClutter: [DecorBox] {
    guard let surface = catSurface else { return [] }
    let widen = cat.length * 0.45
    return pieces.compactMap { placement in
      let size = placement.piece.kind.size
      let centre = SIMD2(placement.centre.x, placement.centre.y)
      guard abs(placement.centre.z - cat.spot.z) < 0.15, size.z >= 0.1,
        centre == simd_clamp(centre, surface.min, surface.max)
      else { return nil }
      return DecorBox(
        centre: centre, half: [size.x / 2 + widen, size.y / 2 + widen], yaw: placement.yaw)
    }
  }

  /// `point`, moved out of anything standing on the cat's top to the nearest side that stays
  /// between `low` and `high` and clear of everything else on it.
  func clearOfClutter(
    _ point: SIMD2<Float>, within low: SIMD2<Float>, _ high: SIMD2<Float>
  ) -> SIMD2<Float> {
    let clutter = catClutter
    let isBlocked = { (spot: SIMD2<Float>) in clutter.contains { $0.contains(spot) } }
    guard let box = clutter.first(where: { $0.contains(point) }) else { return point }
    let axes = DecorBox.axes(box.yaw)
    let offset = point - box.centre
    let along = SIMD2(simd_dot(offset, axes.0), simd_dot(offset, axes.1))
    let step: Float = 0.01
    let exits = [
      point + axes.0 * (box.half.x - along.x + step),
      point - axes.0 * (box.half.x + along.x + step),
      point + axes.1 * (box.half.y - along.y + step),
      point - axes.1 * (box.half.y + along.y + step),
    ]
    var fits = exits.map { simd_clamp($0, low, high) }.filter { !isBlocked($0) }
    if fits.isEmpty {
      // Clutter meets clutter or the top's edge: the nearest open spot, 5 cm apart.
      for x in stride(from: low.x, through: high.x, by: 0.05) {
        for y in stride(from: low.y, through: high.y, by: 0.05) where !isBlocked([x, y]) {
          fits.append([x, y])
        }
      }
    }
    return fits.min { simd_distance($0, point) < simd_distance($1, point) } ?? point
  }

  /// How far along the straight line from `start` to `end` the cat gets before something on its
  /// top is in the way. A cat already among clutter goes where it was going.
  func catReach(from start: SIMD2<Float>, to end: SIMD2<Float>) -> SIMD2<Float> {
    let clutter = catClutter
    let isBlocked = { (point: SIMD2<Float>) in clutter.contains { $0.contains(point) } }
    guard !clutter.isEmpty, !isBlocked(start) else { return end }
    let distance = simd_distance(start, end)
    let steps = max(Int(distance / 0.05), 1)
    var reached = start
    for step in 1...steps {
      let point = start + (end - start) * (Float(step) / Float(steps))
      if isBlocked(point) { return reached }
      reached = point
    }
    return end
  }
}

@MainActor
extension CatTrip.Leg {
  /// This leg, with a walk stopped short of what stands on the cat's top, starting from `start`.
  /// Returns where the cat is after it.
  func clear(of layout: GenzLayout, from start: SIMD2<Float>) -> (leg: Self, end: SIMD2<Float>) {
    switch self {
    case .walk(let to, let speed, let action):
      let reach = layout.catReach(from: start, to: to)
      return (.walk(to: reach, speed: speed, action: action), reach)
    case .hold:
      return (self, start)
    }
  }
}

@MainActor
extension Array where Element == CatTrip.Leg {
  /// These legs with every walk stopped short of what stands on the cat's top.
  func clear(of layout: GenzLayout, from start: SIMD2<Float>) -> [CatTrip.Leg] {
    var at = start
    return map { leg in
      let cleared = leg.clear(of: layout, from: at)
      at = cleared.end
      return cleared.leg
    }
  }
}
