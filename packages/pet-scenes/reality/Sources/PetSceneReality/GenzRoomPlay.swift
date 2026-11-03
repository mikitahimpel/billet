import CoreGraphics
import Foundation
import Pet
import PetScene
import RealityKit
import simd

/// The toys on a styled room's cat floor, and the game being played with one.
@MainActor
final class RoomToys {
  var entities: [CatToy: Entity] = [:]
  /// Where each toy lies when nobody holds it, on the floor plane.
  var resting: [CatToy: SIMD2<Float>] = [:]
  var rolling: [CatToy: RollingToy] = [:]
  /// The toy the finger holds, and where it is on the floor.
  var held: CatToy?
  var heldAt: SIMD2<Float>?
  var heldSpeed: Float = 0
  var heldMoved = -Double.infinity
  var pursuit: CatPursuit?
  var lastStep: Double?
  var delta = 1.0 / 60
  /// The feather's twitch while the wand is held.
  var twitch: Float = 0

  /// Where the held-up cat hangs over the floor, and since when.
  var liftedAt: SIMD2<Float>?
  var liftedClock = 0.0
  /// The treat between the fingers, where it is, and whether the cat has it already.
  var treat: Entity?
  var treatJar: Entity?
  var treatAt: SIMD2<Float>?
  var treatTaken = false
  /// The meal in the bowl: from when, and how long the cat eats it.
  var mealStart: Double?
  var mealLength = 0.0
  /// How full the bowl is from a meal put down, where a room keeps no bowl of its own.
  var meal: Float?
}

extension GenzRoom {
  /// Plays the reactions to play, food, lifting, calling and the partner.
  func showPlay(_ response: CatPlayResponse) {
    switch response.reaction {
    case .partnerLove:
      purr.heart(at: screen.cat)
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

  // MARK: - Building

  private var toyHeight: Float { layout.cat.spot.scene.y }

  /// A spot on the cat's floor turned `turn` from the side facing the camera, `reach` cat
  /// lengths from its place.
  func floorSpot(_ turn: Float, _ reach: Float) -> SIMD2<Float> {
    let eye = SIMD2(camera.position.x, camera.position.z)
    let heading = CatTrip.heading(from: home, to: eye) + turn
    return layout.onCatSurface(
      home + SIMD2(-sin(heading), -cos(heading)) * layout.cat.length * reach)
  }

  func floorPoint(_ spot: SIMD2<Float>, lift: Float = 0) -> SIMD3<Float> {
    SIMD3(spot.x, toyHeight + lift, spot.y)
  }

  func buildToys() {
    let length = layout.cat.length
    let made = CatToyModels.make(length: length)
    let spots: [CatToy: SIMD2<Float>] = [
      .ball: floorSpot(-0.9, 1.05), .yarn: floorSpot(-1.6, 1.25), .laser: floorSpot(1.7, 1.15),
      .wand: floorSpot(1.05, 1.2),
    ]
    for (toy, entity) in made {
      guard let spot = spots[toy] else { continue }
      entity.name = "genz-toy-\(toy.rawValue)"
      entity.position = floorPoint(spot, lift: CatToyModels.lift(toy, length: length))
      entity.orientation = simd_quatf(angle: Float.random(in: 0..<(2 * .pi)), axis: [0, 1, 0])
      room.addChild(entity)
      toys.entities[toy] = entity
      toys.resting[toy] = spot
      if toy.isThrown {
        toys.rolling[toy] = RollingToy(
          at: spot, bounds: toyBounds, grip: toy == .ball ? 0.35 : 0.12)
      }
    }
  }

  /// Where toys can go: the top the cat lives on, a little in from its edges.
  private var toyBounds: (min: SIMD2<Float>, max: SIMD2<Float>)? {
    guard let surface = layout.catSurface else {
      let reach = SIMD2<Float>(repeating: layout.cat.length * 2.5)
      return (home - reach, home + reach)
    }
    let margin = SIMD2<Float>(repeating: layout.cat.length * 0.12)
    return (surface.min + margin, simd_max(surface.max - margin, surface.min + margin))
  }

  // MARK: - Touch

  /// What a finger at `point` is on: the cat, a toy, or nothing the cat cares about.
  func touchTarget(at point: CGPoint) -> CatTouchTarget {
    if isOverCat(point) { return .cat }
    var nearest: (toy: CatToy, distance: CGFloat)?
    for toy in CatToy.allCases {
      guard let at = toyPlace(toy), let shown = camera.project(floorPoint(at), in: viewSize)
      else { continue }
      let distance = hypot(shown.x - point.x, shown.y - point.y)
      if distance < Self.toyReach, distance < nearest?.distance ?? .infinity {
        nearest = (toy, distance)
      }
    }
    return nearest.map { .toy($0.toy) } ?? .nothing
  }

  /// How close a finger must come to a toy on screen to take it, in points.
  static var toyReach: CGFloat { 44 }

  /// Where `toy` is on the floor now.
  func toyPlace(_ toy: CatToy) -> SIMD2<Float>? {
    if toys.held == toy, let at = toys.heldAt { return at }
    if let rolling = toys.rolling[toy] { return rolling.position }
    return toys.resting[toy]
  }

  /// The floor point under a finger at `point`, kept to where toys can go.
  func floorUnder(_ point: CGPoint) -> SIMD2<Float>? {
    let size = SIMD2(Float(viewSize.width), Float(viewSize.height))
    guard
      let spot = NookiFloorRay.floorPoint(
        under: SIMD2(Float(point.x), Float(point.y)), viewSize: size, camera: camera.position,
        target: camera.target, verticalFieldOfView: camera.fieldOfView, height: toyHeight)
    else { return nil }
    guard let bounds = toyBounds else { return spot }
    return simd_clamp(spot, bounds.min, bounds.max)
  }

  /// The finger takes `toy` and moves it to the floor under `point`: the wand's feather or the
  /// laser's dot follows it, a ball is held under it.
  func carry(_ toy: CatToy, to point: CGPoint) {
    guard let spot = floorUnder(point) else { return }
    let first = toys.held != toy
    if let was = toys.heldAt, !first {
      let moved = simd_distance(was, spot)
      if moved > layout.cat.length * 0.01 { toys.heldMoved = clock }
      // Drags arrive about once a frame.
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

  /// The finger lets go. A thrown toy rolls off with `velocity`, in points a second on screen.
  func release(_ toy: CatToy, velocity: CGSize, at point: CGPoint) {
    defer {
      toys.held = nil
      toys.heldAt = nil
    }
    guard toy.isThrown else {
      if let at = toys.heldAt { toys.resting[toy] = at }
      return
    }
    let ahead = CGPoint(
      x: point.x + velocity.width * 0.1, y: point.y + velocity.height * 0.1)
    guard let from = toys.heldAt ?? floorUnder(point), let to = floorUnder(ahead) else { return }
    var throwSpeed = (to - from) / 0.1
    let most = layout.cat.length * 5
    if simd_length(throwSpeed) > most { throwSpeed = simd_normalize(throwSpeed) * most }
    toys.rolling[toy]?.position = from
    toys.rolling[toy]?.velocity = throwSpeed
    if simd_length(throwSpeed) > layout.cat.length * 0.4 { offerToy(toy) }
  }

  /// A tap on a ball or the yarn sends it rolling a little, away from the camera.
  func nudge(_ toy: CatToy) {
    guard toy.isThrown, let at = toyPlace(toy) else { return }
    let eye = SIMD2(camera.position.x, camera.position.z)
    let away = simd_normalize(at - eye + SIMD2(0.001, 0))
    let turn = Float.random(in: -0.6...0.6)
    let direction = SIMD2(
      away.x * cos(turn) - away.y * sin(turn), away.x * sin(turn) + away.y * cos(turn))
    toys.rolling[toy]?.velocity = direction * layout.cat.length * 2.2
    offerToy(toy)
  }

  /// Tells the play machine a toy moved, and starts a game if the cat is keen.
  private func offerToy(_ toy: CatToy) {
    guard world.activity == .sleeping, opening == nil, hasCat else { return }
    if toys.pursuit?.toy == toy, toys.pursuit?.isDone == false { return }
    guard let response = hands.play.handle(.toyMoved(toy), at: clock) else { return }
    _ = show(response)
  }

  private func startPursuit(of toy: CatToy, response: CatPlayResponse) {
    if let tripKind {
      guard tripKind != .delivery, tripKind != .greeting else { return }
      endTrip()
    }
    let spot = SIMD2(catHolder.position.x, catHolder.position.z)
    var fetch: SIMD2<Float>?
    if case .chase(_, true) = response.reaction { fetch = floorSpot(0, 0.9) }
    toys.pursuit = CatPursuit(
      toy: toy, from: spot, heading: bodyHeading, length: layout.cat.length, fetchTo: fetch,
      at: clock)
    purr.feel(.nudge)
  }

  // MARK: - Each frame

  /// Moves the toys on: the rolling ones roll, the held one follows the finger, and the laser's
  /// dot shows while the pointer is held.
  func stepToys() {
    let delta = min(clock - (toys.lastStep ?? clock), 0.1)
    toys.lastStep = clock
    toys.delta = delta
    if clock - toys.heldMoved > 0.3 { toys.heldSpeed *= 0.8 }
    let length = layout.cat.length
    for toy in [CatToy.ball, .yarn] {
      guard var rolling = toys.rolling[toy], let entity = toys.entities[toy] else { continue }
      if toys.held == toy, let at = toys.heldAt { rolling.position = at }
      let before = rolling.position
      if toys.pursuit?.holdsToy == true, toys.pursuit?.toy == toy,
        let mouth = rig?.mouth().map({ room.convert(position: $0, from: nil) })
      {
        rolling.position = SIMD2(mouth.x, mouth.z)
        rolling.velocity = .zero
        entity.position = mouth
      } else {
        rolling.step(delta)
        let radius = CatToyModels.lift(toy, length: length)
        entity.position = floorPoint(rolling.position, lift: radius)
        let moved = rolling.position - before
        if simd_length(moved) > 0.0001 {
          // Rolls, turning about the axis across its way.
          let axis = simd_normalize(SIMD3(moved.y, 0, -moved.x))
          entity.orientation =
            simd_quatf(angle: simd_length(moved) / radius, axis: axis) * entity.orientation
        }
      }
      toys.rolling[toy] = rolling
    }
    stepWand(delta)
    stepLaser()
    stepMeal()
    if toys.pursuit == nil, let held = toys.held, let at = toyPlace(held) {
      // Not playing, it still watches the toy go by.
      if clock - toys.heldMoved < 0.4 { headLook(at: floorPoint(at), for: 0.6) }
    }
  }

  private func stepWand(_ delta: Double) {
    guard let wand = toys.entities[.wand] else { return }
    let length = layout.cat.length
    guard toys.held == .wand, let at = toys.heldAt else {
      if let rest = toys.resting[.wand] {
        wand.position = floorPoint(rest, lift: CatToyModels.lift(.wand, length: length))
        if let stick = wand.findEntity(named: "stick") {
          stick.orientation = simd_quatf(angle: 0, axis: [1, 0, 0])
        }
      }
      return
    }
    toys.twitch += Float(delta) * (4 + min(toys.heldSpeed / length, 4) * 3)
    let hop = abs(sin(toys.twitch * 2.3)) * length * 0.06
    wand.position = floorPoint(at, lift: length * 0.1 + hop)
    // The stick rises from the feather towards the camera, the way a hand holds it.
    let eye = SIMD2(camera.position.x, camera.position.z)
    let towards = CatTrip.heading(from: at, to: eye)
    wand.orientation = simd_quatf(angle: towards + .pi, axis: [0, 1, 0])
    wand.findEntity(named: "stick")?.orientation = simd_quatf(angle: 0.9, axis: [1, 0, 0])
    wand.findEntity(named: "feather")?.orientation = simd_quatf(
      angle: sin(toys.twitch * 3.1) * 0.5, axis: [0, 1, 0])
  }

  private func stepLaser() {
    let laserOn = toys.held == .laser && toys.heldAt != nil
    guard laserOn || tripKind == nil else { return }
    if laserOn, let at = toys.heldAt {
      lightDot.isEnabled = true
      // As high as the chase's dot, clear of the top it lands on.
      lightDot.position = floorPoint(at, lift: 0.012)
      lightDot.components.set(OpacityComponent(opacity: 0.95))
    } else if toys.pursuit?.toy == .laser || lightDot.isEnabled {
      lightDot.isEnabled = false
    }
  }

  /// Moves the game on and returns the cat's pose, or nil when no game is on.
  func stepPursuit() -> CatTrip.Pose? {
    guard var pursuit = toys.pursuit else { return nil }
    if world.activity != .sleeping || reduceMotion {
      toys.pursuit = nil
      return nil
    }
    let toy = pursuit.toy
    var target = toyPlace(toy)
    var speed: Float = 0
    switch toy {
    case .wand, .laser:
      if toys.held != toy { target = nil }
      speed = clock - toys.heldMoved < 0.3 ? max(toys.heldSpeed, layout.cat.length * 0.3) : 0
    case .ball, .yarn:
      speed = toys.rolling[toy]?.speed ?? 0
      if toys.held == toy { speed = max(speed, layout.cat.length * 0.3) }
    }
    let event = pursuit.step(
      target: target, targetSpeed: speed, at: clock, delta: max(toys.delta, 1.0 / 120))
    toys.pursuit = pursuit
    switch event {
    case .caught:
      if toy.isThrown, pursuit.fetchTo == nil {
        // Batted away again.
        let away = SIMD2<Float>(Float.random(in: -1...1), Float.random(in: -1...1))
        toys.rolling[toy]?.velocity = away * layout.cat.length * 0.8
      }
      if let response = hands.play.handle(.toyCaught(toy), at: clock) {
        for event in show(response) { report?(event) }
      }
    case .dropped(let at):
      toys.rolling[toy]?.position = at
      toys.rolling[toy]?.velocity = .zero
      purr.feel(.settle)
      purr.heart(at: screen.cat)
    case nil: break
    }
    let pose = pursuit.pose
    catHolder.position = floorPoint(layout.onCatSurface(pose.spot))
    screen.cat = camera.project(
      catHolder.position + [0, layout.cat.length * 0.55, 0], in: viewSize)
    if let at = target { headLook(at: floorPoint(at, lift: layout.cat.length * 0.05), for: 0.3) }
    if pursuit.isDone {
      toys.pursuit = nil
      walkHome(from: SIMD2(catHolder.position.x, catHolder.position.z), heading: pose.heading)
    }
    return pose
  }

  /// Walks back to its place from wherever a game, a call or a carry left it.
  func walkHome(from spot: SIMD2<Float>, heading: Float) {
    trip = CatTrip(
      from: spot, heading: heading,
      legs: [
        .hold(behaviour.playable(.sit), seconds: 0.8),
        .walk(to: home, speed: walkSpeed),
        .hold(behaviour.playable(.sit), seconds: 0.5, facing: homeFront),
      ], at: clock)
    tripKind = .wander
  }
}
