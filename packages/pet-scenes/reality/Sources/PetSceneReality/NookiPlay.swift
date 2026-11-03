import CoreGraphics
import Foundation
import Pet
import PetScene
import RealityKit
import simd

extension NookiDiorama {
  /// Plays the reactions to play, food, lifting, calling and the partner.
  func showPlay(_ response: CatPlayResponse) {
    switch response.reaction {
    case .partnerLove:
      purr.heart(at: catPointOnScreen)
    case .stalk(let toy), .chase(let toy, _):
      startPursuit(of: toy, response: response)
    case .watch(let toy):
      if let at = toyPlace(toy) { headLook(at: floorPoint(at), for: 1.2) }
    case .caught:
      behaviour.react(.tap, at: clock)
    case .lean, .flick, .grab, .eat, .takeTreat, .refuse, .dangle, .settle, .come, .ignore,
      .trick:
      break
    }
  }

  /// Where the cat's head is on screen, for hearts that are not under a finger.
  var catPointOnScreen: CGPoint? { catBody().map { CGPoint(x: $0.head.x, y: $0.head.y) } }

  /// The cat's length in the diorama's metres, for sizing toys and games.
  static let catReach: Float = 0.3
  /// The toys Nooki adds. Its own yarn keeps its physics and its own game.
  nonisolated static let addedToys: [CatToy] = [.wand, .laser, .ball]

  func floorPoint(_ spot: SIMD2<Float>, lift: Float = 0) -> SIMD3<Float> {
    SIMD3(spot.x, lift, spot.y)
  }

  private var toyBounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
    (NookiFloorPlan.floorMin + 0.06, NookiFloorPlan.floorMax - 0.06)
  }

  func buildToys() {
    let made = CatToyModels.make(length: Self.catReach)
    let spots: [CatToy: SIMD2<Float>] = [
      .wand: [-0.32, 0.42], .laser: [0.5, 0.18], .ball: [-0.12, 0.5],
    ]
    for toy in Self.addedToys {
      guard let entity = made[toy], let spot = spots[toy] else { continue }
      entity.name = "nooki-toy-\(toy.rawValue)"
      entity.position = floorPoint(spot, lift: CatToyModels.lift(toy, length: Self.catReach))
      entity.orientation = simd_quatf(angle: Float.random(in: 0..<(2 * .pi)), axis: [0, 1, 0])
      room.addChild(entity)
      toys.entities[toy] = entity
      toys.resting[toy] = spot
      if toy.isThrown { toys.rolling[toy] = RollingToy(at: spot, bounds: toyBounds, grip: 0.35) }
    }
    room.addChild(laserDot)
  }

  // MARK: - Touch

  private var screenSize: CGSize {
    CGSize(width: CGFloat(fittedSize.x), height: CGFloat(fittedSize.y))
  }

  private func project(_ point: SIMD3<Float>) -> CGPoint? {
    GenzCamera.project(
      point, from: camera.position, towards: NookiCamera.target, fieldOfView: Self.fieldOfView,
      in: screenSize)
  }

  /// What a finger at `point` is on, for the toys Nooki adds; nil leaves it to the room's own
  /// entity touches.
  func toyTarget(at point: CGPoint) -> CatToy? {
    var nearest: (toy: CatToy, distance: CGFloat)?
    for toy in Self.addedToys {
      guard let at = toyPlace(toy), let shown = project(floorPoint(at)) else { continue }
      let distance = hypot(shown.x - point.x, shown.y - point.y)
      if distance < GenzRoom.toyReach, distance < nearest?.distance ?? .infinity {
        nearest = (toy, distance)
      }
    }
    return nearest?.toy
  }

  func toyPlace(_ toy: CatToy) -> SIMD2<Float>? {
    if toys.held == toy, let at = toys.heldAt { return at }
    if let rolling = toys.rolling[toy] { return rolling.position }
    return toys.resting[toy]
  }

  private func floorUnder(_ point: CGPoint) -> SIMD2<Float>? {
    guard
      let spot = NookiFloorRay.floorPoint(
        under: SIMD2(Float(point.x), Float(point.y)), viewSize: fittedSize,
        camera: camera.position, target: NookiCamera.target, verticalFieldOfView: Self.fieldOfView)
    else { return nil }
    return simd_clamp(spot, toyBounds.min, toyBounds.max)
  }

  func carry(_ toy: CatToy, to point: CGPoint) {
    guard let spot = floorUnder(point) else { return }
    let first = toys.held != toy
    if let was = toys.heldAt, !first {
      let moved = simd_distance(was, spot)
      if moved > Self.catReach * 0.01 { toys.heldMoved = clock }
      toys.heldSpeed = toys.heldSpeed * 0.7 + moved * 60 * 0.3
    }
    toys.held = toy
    toys.heldAt = spot
    if toy.isThrown { toys.rolling[toy]?.velocity = .zero }
    if first {
      toys.heldSpeed = 0
      toys.heldMoved = clock
      if !toy.isThrown { offerToy(toy) }
    }
  }

  func release(_ toy: CatToy, velocity: CGSize, at point: CGPoint) {
    defer {
      toys.held = nil
      toys.heldAt = nil
    }
    guard toy.isThrown else {
      if let at = toys.heldAt { toys.resting[toy] = at }
      return
    }
    let ahead = CGPoint(x: point.x + velocity.width * 0.1, y: point.y + velocity.height * 0.1)
    guard let from = toys.heldAt ?? floorUnder(point), let to = floorUnder(ahead) else { return }
    var throwSpeed = (to - from) / 0.1
    let most = Self.catReach * 5
    if simd_length(throwSpeed) > most { throwSpeed = simd_normalize(throwSpeed) * most }
    toys.rolling[toy]?.position = from
    toys.rolling[toy]?.velocity = throwSpeed
    if simd_length(throwSpeed) > Self.catReach * 0.4 { offerToy(toy) }
  }

  func nudge(_ toy: CatToy) {
    guard toy.isThrown, let at = toyPlace(toy) else { return }
    let bed = SIMD2(Self.bedSpot.x, Self.bedSpot.z)
    let away = simd_normalize(at - bed + SIMD2(0.001, 0))
    toys.rolling[toy]?.velocity = away * Self.catReach * 2.2
    offerToy(toy)
  }

  private func offerToy(_ toy: CatToy) {
    guard world.activity == .sleeping, !noteIsOpen, opening == nil, hasCat, !yarnPlay.isPlaying
    else { return }
    if toys.pursuit?.toy == toy, toys.pursuit?.isDone == false { return }
    guard let response = hands.play.handle(.toyMoved(toy), at: clock) else { return }
    _ = show(response)
  }

  private func startPursuit(of toy: CatToy, response: CatPlayResponse) {
    guard trip == nil else { return }
    let from = SIMD2(catHolder.position(relativeTo: room).x, catHolder.position(relativeTo: room).z)
    let forward = catHolder.orientation(relativeTo: room).act([0, 0, -1])
    var fetch: SIMD2<Float>?
    if case .chase(_, true) = response.reaction {
      let eye = SIMD2(camera.position.x, camera.position.z)
      fetch = simd_clamp(
        CatTrip.towards(eye, from: SIMD2(Self.bedSpot.x, Self.bedSpot.z), upTo: 0.35),
        toyBounds.min, toyBounds.max)
    }
    toys.pursuit = CatPursuit(
      toy: toy, from: from, heading: atan2(-forward.x, -forward.z), length: Self.catReach,
      fetchTo: fetch, at: clock)
    purr.feel(.nudge)
  }

  // MARK: - Each frame

  var isPlayingWithToys: Bool {
    toys.pursuit != nil || toys.held != nil || toys.rolling.values.contains { $0.speed > 0 }
      || toys.liftedAt != nil || toys.mealStart != nil || toys.treatAt != nil
  }

  func stepToys(_ delta: Double) {
    toys.delta = delta
    if clock - toys.heldMoved > 0.3 { toys.heldSpeed *= 0.8 }
    for toy in [CatToy.ball] {
      guard var rolling = toys.rolling[toy], let entity = toys.entities[toy] else { continue }
      if toys.held == toy, let at = toys.heldAt { rolling.position = at }
      let before = rolling.position
      let radius = CatToyModels.lift(toy, length: Self.catReach)
      if toys.pursuit?.holdsToy == true, toys.pursuit?.toy == toy,
        let mouth = rig?.mouth().map({ room.convert(position: $0, from: nil) })
      {
        rolling.position = SIMD2(mouth.x, mouth.z)
        rolling.velocity = .zero
        entity.position = mouth
      } else {
        rolling.step(delta)
        entity.position = floorPoint(rolling.position, lift: radius)
        let moved = rolling.position - before
        if simd_length(moved) > 0.0001 {
          let axis = simd_normalize(SIMD3(moved.y, 0, -moved.x))
          entity.orientation =
            simd_quatf(angle: simd_length(moved) / radius, axis: axis) * entity.orientation
        }
      }
      toys.rolling[toy] = rolling
    }
    stepWand(delta)
    stepMeal()
    let laserOn = toys.held == .laser && toys.heldAt != nil
    laserDot.isEnabled = laserOn
    if laserOn, let at = toys.heldAt { laserDot.position = floorPoint(at, lift: 0.003) }
    if toys.pursuit == nil, let held = toys.held, let at = toyPlace(held),
      clock - toys.heldMoved < 0.4
    {
      headLook(at: floorPoint(at), for: 0.6)
    }
  }

  private func stepWand(_ delta: Double) {
    guard let wand = toys.entities[.wand] else { return }
    let length = Self.catReach
    guard toys.held == .wand, let at = toys.heldAt else {
      if let rest = toys.resting[.wand] {
        wand.position = floorPoint(rest, lift: CatToyModels.lift(.wand, length: length))
        wand.findEntity(named: "stick")?.orientation = simd_quatf(angle: 0, axis: [1, 0, 0])
      }
      return
    }
    toys.twitch += Float(delta) * (4 + min(toys.heldSpeed / length, 4) * 3)
    let hop = abs(sin(toys.twitch * 2.3)) * length * 0.06
    wand.position = floorPoint(at, lift: length * 0.1 + hop)
    let eye = SIMD2(camera.position.x, camera.position.z)
    wand.orientation = simd_quatf(
      angle: CatTrip.heading(from: at, to: eye) + .pi, axis: [0, 1, 0])
    wand.findEntity(named: "stick")?.orientation = simd_quatf(angle: 0.9, axis: [1, 0, 0])
    wand.findEntity(named: "feather")?.orientation = simd_quatf(
      angle: sin(toys.twitch * 3.1) * 0.5, axis: [0, 1, 0])
  }

  /// Moves the game on and returns the cat's pose, or nil when no game is on.
  func stepPursuit() -> CatTrip.Pose? {
    guard var pursuit = toys.pursuit else { return nil }
    if world.activity != .sleeping || reduceMotion || noteIsOpen {
      toys.pursuit = nil
      return nil
    }
    let toy = pursuit.toy
    var target = toyPlace(toy)
    var speed: Float = 0
    switch toy {
    case .wand, .laser:
      if toys.held != toy { target = nil }
      speed = clock - toys.heldMoved < 0.3 ? max(toys.heldSpeed, Self.catReach * 0.3) : 0
    case .ball, .yarn:
      speed = toys.rolling[toy]?.speed ?? 0
      if toys.held == toy { speed = max(speed, Self.catReach * 0.3) }
    }
    let event = pursuit.step(
      target: target, targetSpeed: speed, at: clock, delta: max(toys.delta, 1.0 / 120))
    toys.pursuit = pursuit
    switch event {
    case .caught:
      if toy.isThrown, pursuit.fetchTo == nil {
        let away = SIMD2<Float>(Float.random(in: -1...1), Float.random(in: -1...1))
        toys.rolling[toy]?.velocity = away * Self.catReach * 0.8
      }
      if let response = hands.play.handle(.toyCaught(toy), at: clock) {
        for event in show(response) { report?(event) }
      }
    case .dropped(let at):
      toys.rolling[toy]?.position = at
      toys.rolling[toy]?.velocity = .zero
      purr.feel(.settle)
      purr.heart(at: catPointOnScreen)
    case nil: break
    }
    if let at = target { headLook(at: floorPoint(at, lift: 0.02), for: 0.3) }
    if pursuit.isDone {
      toys.pursuit = nil
      walkHome(from: pursuit.spot, heading: pursuit.heading)
    }
    return pursuit.pose
  }

  /// Walks back to the bed from wherever a game, a call or a carry left it.
  func walkHome(from spot: SIMD2<Float>, heading: Float) {
    let bed = SIMD2(Self.bedSpot.x, Self.bedSpot.z)
    let rest = NookiChoreography.restHeading
    trip = CatTrip(
      from: spot, heading: heading,
      legs: [
        .hold(behaviour.playable(.sit), seconds: 0.8),
        .walk(to: bed, speed: Self.walkPace),
        .hold(behaviour.playable(.sit), seconds: 0.5, facing: bed + SIMD2(-sin(rest), -cos(rest))),
      ], at: clock)
  }
}
