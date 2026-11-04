import Foundation
import Pet
import simd

extension GenzLayout {
  /// The levels the cat can get to from `start` by jumping, `start` among them.
  func catReachableLevels(from start: Int) -> Set<Int> {
    let levels = catLevels
    var reached: Set<Int> = [start]
    var frontier = [start]
    while let current = frontier.popLast() {
      guard let here = levels.first(where: { $0.id == current }) else { continue }
      for other in levels where !reached.contains(other.id) {
        guard catJump(from: here, to: other) != nil else { continue }
        reached.insert(other.id)
        frontier.append(other.id)
      }
    }
    return reached
  }
}

extension GenzRoom {
  /// Works out where the brain's step sends the cat and the way there: the spot and level of its
  /// target, a spot there its resting body fits for a resting clip, and the walks and jumps.
  func planWay(for frame: CatBrainFrame) {
    let started = footingNow()
    defer { footing.cost.plan = max(footing.cost.plan, footingNow() - started) }
    var (goal, level) = resolveLevel(frame.target)
    let base = rig?.info[behaviour.playable(frame.action)]?.base ?? .stand
    if base != .stand {
      goal = layout.catRestSpot(near: goal, on: level, heading: headingFor(frame) ?? bodyHeading)
    }
    var ways = layout.catWay(from: catSpot, on: footing.level, to: goal, on: level)
    // Somewhere it cannot get to without going through something: as near as it gets.
    var end = catSpot
    var endLevel = footing.level
    for way in ways {
      switch way {
      case .walk(let to, let on): (end, endLevel) = (to, on)
      case .jump(let jump): (end, endLevel) = (jump.to, jump.toLevel)
      }
    }
    brainBody.ways = ways
    brainBody.goal = end
    brainBody.goalLevel = endLevel
  }

  /// ``resolve(_:)`` with the level the spot is on: the cat's own top, unless the target is a
  /// piece or rug it gets to by jumping.
  func resolveLevel(_ target: CatTarget) -> (SIMD2<Float>, Int) {
    let home = layout.catHomeLevel
    switch target {
    case .stay: return (catSpot, footing.level)
    case .affordance(let kind):
      guard let found = place(kind), found.affordance.reachable, found.level != home,
        let level = layout.catLevel(found.level)
      else { break }
      let spot =
        layout.catSpot(near: found.spot, on: level, obstacles: layout.catObstacles(on: level.id))
        ?? found.spot
      return (spot, level.id)
    case .home, .camera, .roam: break
    }
    return (resolve(target), home)
  }

  /// When something has been put where the settled cat is (a piece moved onto it, here or by
  /// the partner), the cat gets up and goes to the nearest spot it fits, and carries on there.
  func makeRoom(for frame: CatBrainFrame) {
    guard !decor.isOn, brainBody.jump == nil else { return }
    let base = rig?.current.flatMap { rig?.info[$0]?.base } ?? .stand
    guard
      layout.catIsCrowded(
        at: catSpot, heading: bodyHeading, on: footing.level, resting: base != .stand)
    else { return }
    planWay(for: frame)
    brainBody.arrived = nil
    brainBody.rest = nil
  }

  /// The jump the cat is in, or the one it is at the take-off of: the pose along its arc. It
  /// crouches on the take-off spot, flies, and lands on the next level, where the footing takes
  /// it over again.
  func stepJump(_ frame: CatBrainFrame) -> CatTrip.Pose? {
    guard brainBody.jump == nil else { return stepJump(brainBody.jump!.jump) }
    guard case .jump(let jump)? = brainBody.ways.first,
      simd_distance(catSpot, jump.from) < layout.cat.length * 0.05
    else { return nil }
    return stepJump(jump)
  }

  /// The pose along `jump`, starting it if it has not.
  func stepJump(_ jump: GenzCatJump) -> CatTrip.Pose? {
    if brainBody.jump == nil {
      let action = jumpAction(up: jump.rise > 0)
      brainBody.jump = (jump, clock, Self.jumpLength(rise: jump.rise), action)
    }
    guard let (jump, start, length, action) = brainBody.jump else { return nil }
    let into = (clock - start) / length
    let heading = CatTrip.heading(from: jump.from, to: jump.to)
    let (lift, land) = airborne(action)
    let from = SIMD3(jump.from.x, groundHeight(at: jump.from, on: jump.fromLevel), jump.from.y)
    let to = SIMD3(jump.to.x, groundHeight(at: jump.to, on: jump.toLevel), jump.to.y)
    guard into < 1 else {
      brainBody.jump = nil
      if !brainBody.ways.isEmpty { brainBody.ways.removeFirst() }
      footing.level = jump.toLevel
      footing.height = GenzSpring(value: to.y)
      catHolder.position = to
      return nil
    }
    let flight = Float(min(max((into - lift) / (land - lift), 0), 1))
    let apex = max(from.y, to.y) + layout.cat.length * 0.25
    // A curve through take-off, the top of the leap and the landing.
    let along = flight * flight * (3 - 2 * flight)
    let height =
      (1 - flight) * (1 - flight) * from.y + 2 * (1 - flight) * flight
      * (2 * apex - (from.y + to.y) / 2)
      + flight * flight * to.y
    let place = from + (to - from) * along
    catHolder.position = SIMD3(
      place.x, flight > 0 && flight < 1 ? height : flight == 0 ? from.y : to.y, place.z)
    screen.cat = camera.project(
      catHolder.position + [0, layout.cat.length * 0.55, 0], in: viewSize)
    return CatTrip.Pose(
      spot: SIMD2(place.x, place.z), heading: heading, action: action, speed: 0, leg: 0,
      progress: into, isDone: false)
  }

  /// How long a jump takes, take-off to landing, in seconds: longer the higher it goes.
  static func jumpLength(rise: Float) -> Double { 0.75 + 0.12 * Double(abs(rise)) }

  /// The clip for a jump up or down: its own, the other way's, a pounce, or a walk.
  private func jumpAction(up: Bool) -> CatAction {
    let order: [CatAction] = up ? [.jumpUp, .jumpDown, .pounce] : [.jumpDown, .jumpUp, .pounce]
    return order.first(where: behaviour.has) ?? .walk
  }

  /// When in `action`'s clip the paws leave the ground and land again, as shares of the clip,
  /// from its measured lowest point; a quarter in and four fifths in for one not measured.
  private func airborne(_ action: CatAction) -> (Double, Double) {
    guard let samples = footing.table?.clips[action.rawValue], samples.count > 2 else {
      return (0.25, 0.8)
    }
    let up = samples.firstIndex { $0 > 0.01 }
    let down = samples.lastIndex { $0 > 0.01 }
    guard let up, let down, down > up else { return (0.25, 0.8) }
    let span = Double(samples.count - 1)
    return (max(Double(up - 1), 0) / span, min(Double(down + 1), span) / span)
  }

  /// The rate a jump's clip plays at so it lasts as long as the jump.
  func jumpRate() -> Float? {
    guard let jump = brainBody.jump, let clip = rig?.info[jump.action] else { return nil }
    return Float(clip.duration / jump.length)
  }
}

extension GenzRoom {
  /// Walks and jumps along ``CatBrainBody/ways`` at `speed`: the pose for this frame, or nil once
  /// the way is done.
  func walkWays(_ step: Float, speed: Float) -> CatTrip.Pose? {
    if let jumping = brainBody.jump {
      return stepJump(jumping.jump)
    }
    let at = catSpot
    let near = layout.cat.length * 0.04
    switch brainBody.ways.first {
    case nil: return nil
    case .jump(let jump)?:
      if simd_distance(at, jump.from) < near * 1.2 { return stepJump(jump) }
      return walk(towards: jump.from, step: step, speed: speed)
    case .walk(let to, _)?:
      if simd_distance(at, to) < near {
        brainBody.ways.removeFirst()
        return walkWays(step, speed: speed)
      }
      return walk(towards: to, step: step, speed: speed)
    }
  }

  private func walk(towards point: SIMD2<Float>, step: Float, speed: Float) -> CatTrip.Pose {
    let at = catSpot
    let gap = point - at
    let distance = simd_length(gap)
    let next = distance < 1e-5 ? point : at + gap / distance * min(speed * step, distance)
    catHolder.position = SIMD3(next.x, catHolder.position.y, next.y)
    screen.cat = camera.project(
      catHolder.position + [0, layout.cat.length * 0.55, 0], in: viewSize)
    return CatTrip.Pose(
      spot: next, heading: CatTrip.heading(from: at, to: point), action: .walk, speed: speed,
      leg: 0, progress: 0, isDone: false)
  }

  /// A trip asked for while the cat is off its own top waits while it goes back up; then it
  /// starts from where the cat is.
  func stepTripHome(_ step: Float) -> CatTrip.Pose? {
    guard let pending = pendingTrip else { return nil }
    let home = layout.catHomeLevel
    if footing.level == home, brainBody.jump == nil {
      pendingTrip = nil
      perch = (catSpot, bodyHeading)
      // The brain works its way out again from here after.
      brainBody.goalFor = nil
      begin(pending.kind, legs: pending.legs)
      return nil
    }
    let goingHome = brainBody.ways.contains { way in
      switch way {
      case .walk(_, let level): level == home
      case .jump(let jump): jump.toLevel == home
      }
    }
    if !goingHome {
      let spot = layout.onCatSurface(self.home)
      brainBody.ways = layout.catWay(from: catSpot, on: footing.level, to: spot, on: home)
      if brainBody.ways.isEmpty {
        // No way back up from here: the trip is let go rather than glide.
        pendingTrip = nil
        return nil
      }
    }
    return walkWays(step, speed: walkSpeed * 1.4)
  }
}
