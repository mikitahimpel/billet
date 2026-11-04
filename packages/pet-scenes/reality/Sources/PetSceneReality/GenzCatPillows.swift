import simd

/// The cat's body seen from above, as a capsule along its heading, in shares of the room's cat
/// length, from where the room places the cat: how far it reaches behind and in front, and half
/// its width. The tail is left out: it curls over what it touches. Each cat's is measured over its
/// clips (``CatModel/footprint``): standing, as it walks; resting, as it sits, loafs and sleeps
/// curled up, which is round and nearly as wide as the cat is long.
struct GenzCatShape: Equatable, Sendable {
  var back: Float
  var front: Float
  var half: Float

  /// The ends of the capsule's middle line, in shares of the length along the heading.
  var ends: (Float, Float) {
    let low = -back + half
    let high = front - half
    return low <= high ? (low, high) : ((front - back) / 2, (front - back) / 2)
  }

  /// The capsule's radius, in shares of the length.
  var radius: Float { max(half, (front + back) / 2 - (ends.1 - ends.0) / 2) }

  /// Points along the capsule's middle line, from tail to nose, for a cat `length` long placed at
  /// `centre` and facing `heading`.
  func spine(at centre: SIMD2<Float>, heading: Float, length: Float) -> [SIMD2<Float>] {
    let forward = SIMD2(-sin(heading), -cos(heading))
    let (low, high) = ends
    return (0...6).map { (index: Int) -> SIMD2<Float> in
      let share: Float = low + (high - low) * Float(index) / 6
      return centre + forward * (share * length)
    }
  }

  /// The widest of the made cats', for a cat the room has no measure of.
  static let widestStanding = GenzCatShape(back: 0.47, front: 0.97, half: 0.48)
  static let widestResting = GenzCatShape(back: 0.38, front: 1.17, half: 0.7)
}

extension GenzLayout {
  /// The pillows on the cat's top, by their index in ``pieces``.
  var catPillows: [Int] {
    guard catSurface != nil else { return [] }
    return pieces.indices.filter { index in
      pieces[index].piece.kind.isPillow && abs(pieces[index].centre.z - cat.spot.z) < 0.15
    }
  }

  /// A pillow's footprint where it stands now.
  func pillowBox(_ index: Int) -> DecorBox {
    let placement = pieces[index]
    let size = placement.piece.kind.size
    return DecorBox(
      centre: [placement.centre.x, placement.centre.y], half: [size.x / 2, size.y / 2],
      yaw: placement.yaw)
  }

  /// The part of a pillow that rests on the seat, which decorating keeps others off (as
  /// `GenzRoom.footprint(of:)` has it): it leans back over the glass above it.
  func pillowSeatBox(_ index: Int) -> DecorBox {
    let placement = pieces[index]
    return DecorBox(
      centre: [placement.centre.x, placement.centre.y],
      half: [placement.piece.kind.pillow.width / 2 - 0.01, 0.25], yaw: placement.yaw)
  }

  /// Whether the cat's resting body, placed at `spot` and facing `heading`, is in a pillow.
  func catRestsInPillow(at spot: SIMD2<Float>, heading: Float) -> Bool {
    let shape = catBody.resting
    let spine = shape.spine(at: spot, heading: heading, length: cat.length)
    let radius = shape.radius * cat.length
    return catPillows.contains { index in
      let box = pillowBox(index)
      return spine.contains { box.distance(to: $0) < radius }
    }
  }

  /// Where the seat's pillows slide to, along the backrest as decorating slides them, so the
  /// cat's resting body at `spot` facing `heading` is in none of them: each pillow it is in goes
  /// out to the nearer side of the body and pushes the ones beyond it along, as a cat settling
  /// against them would, keeping on the seat. A pillow the body is in when the seat's end stops
  /// it goes the other way. Only the pillows that move, with their new middle along the seat.
  func pillowNudges(clearOf spot: SIMD2<Float>, heading: Float) -> [(index: Int, x: Float)] {
    guard let surface = catSurface else { return [] }
    let pillows = catPillows
    guard !pillows.isEmpty else { return [] }
    let shape = catBody.resting
    let spine = shape.spine(at: spot, heading: heading, length: cat.length)
    let radius = shape.radius * cat.length + GenzCatPillows.gap
    let inBody = pillows.filter { index in
      let box = pillowBox(index)
      return spine.contains { box.distance(to: $0) < radius }
    }
    guard !inBody.isEmpty else { return [] }
    // The body's reach along the seat; the pillows stand in a row along it.
    let left = (spine.map(\.x).min() ?? spot.x) - radius
    let right = (spine.map(\.x).max() ?? spot.x) + radius
    let half = Dictionary(
      uniqueKeysWithValues: pillows.map { ($0, pillowSeatBox($0).half.x) })
    var x = Dictionary(uniqueKeysWithValues: pillows.map { ($0, pieces[$0].centre.x) })

    /// Pushes `row`, nearest the body first, out past `edge` towards `sign`, each clear of the
    /// one before it. False when the seat's end stops one short.
    func push(_ row: [Int], from edge: Float, sign: Float) -> Bool {
      var edge = edge
      for index in row {
        let wanted = edge + sign * half[index, default: 0]
        let at = x[index, default: 0]
        let moved = sign < 0 ? min(at, wanted) : max(at, wanted)
        let low = surface.min.x + half[index, default: 0]
        let high = surface.max.x - half[index, default: 0]
        x[index] = min(max(moved, low), high)
        if x[index] != moved { return false }
        edge = moved + sign * (half[index, default: 0] + GenzCatPillows.gap)
      }
      return true
    }
    let sorted = pillows.sorted { pieces[$0].centre.x < pieces[$1].centre.x }
    let leftward = sorted.filter { pieces[$0].centre.x < spot.x }.reversed()
    let rightward = sorted.filter { pieces[$0].centre.x >= spot.x }
    let original = x
    let leftFits = push(Array(leftward), from: left - GenzCatPillows.gap, sign: -1)
    let rightFits = push(rightward, from: right + GenzCatPillows.gap, sign: 1)
    if !leftFits || !rightFits {
      // One side ran out of seat: everything goes the other way.
      x = original
      if !leftFits {
        _ = push(
          sorted.filter { pieces[$0].centre.x >= left }, from: right + GenzCatPillows.gap, sign: 1)
      } else {
        _ = push(
          Array(sorted.filter { pieces[$0].centre.x <= right }.reversed()),
          from: left - GenzCatPillows.gap, sign: -1)
      }
    }
    return pillows.compactMap { index in
      let to = x[index, default: pieces[index].centre.x]
      return abs(to - pieces[index].centre.x) > 1e-4 ? (index, to) : nil
    }
  }
}

enum GenzCatPillows {
  /// How far apart a pillow nudged aside keeps from the cat and from the next pillow.
  static let gap: Float = 0.03
}
