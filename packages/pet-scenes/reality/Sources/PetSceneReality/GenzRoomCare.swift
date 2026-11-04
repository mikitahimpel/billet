import CoreGraphics
import Foundation
import Pet
import PetScene
import RealityKit
import simd

/// Food, treats, being picked up and put down, being called and doing tricks, in a styled room.
extension GenzRoom {
  // MARK: - Building

  func buildCareProps() {
    let length = layout.cat.length
    let jar = ModelEntity(
      mesh: LowPoly.cylinder(height: length * 0.2, radius: length * 0.075),
      materials: [
        SimpleMaterial(
          color: .init(red: 0.86, green: 0.93, blue: 0.97, alpha: 0.55), roughness: 0.15,
          isMetallic: false)
      ])
    let lid = ModelEntity(
      mesh: LowPoly.cylinder(height: length * 0.03, radius: length * 0.08),
      materials: [
        SimpleMaterial(color: .init(red: 0.9, green: 0.45, blue: 0.4, alpha: 1), isMetallic: false)
      ])
    lid.position.y = length * 0.115
    jar.addChild(lid)
    for index in 0..<4 {
      let bit = Self.treatModel(length: length * 0.8)
      bit.position = [
        Float(index % 2) * length * 0.04 - length * 0.02,
        -length * 0.06 + Float(index / 2) * length * 0.04,
        0,
      ]
      jar.addChild(bit)
    }
    let spot = floorSpot(0.5, 1.3)
    jar.position = floorPoint(spot, lift: length * 0.1)
    jar.name = "genz-treats"
    room.addChild(jar)
    toys.treatJar = jar
    let treat = Self.treatModel(length: length)
    treat.isEnabled = false
    room.addChild(treat)
    toys.treat = treat
  }

  /// A little fish-shaped treat.
  static func treatModel(length: Float) -> Entity {
    let colour = SimpleMaterial(
      color: .init(red: 0.78, green: 0.5, blue: 0.27, alpha: 1), roughness: 0.8, isMetallic: false)
    let body = ModelEntity(mesh: LowPoly.sphere(radius: length * 0.035), materials: [colour])
    body.scale = [1.6, 0.7, 0.9]
    let tail = ModelEntity(
      mesh: .generateBox(size: [length * 0.03, length * 0.035, length * 0.008]), materials: [colour]
    )
    tail.position = [-length * 0.06, 0, 0]
    tail.orientation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1])
    let treat = Entity()
    treat.addChild(body)
    treat.addChild(tail)
    return treat
  }

  // MARK: - Where a tap lands

  /// What a finger at `point` is on, for taps: the cat and its things, then open floor.
  func tapTarget(at point: CGPoint) -> CatTouchTarget {
    let target = touchTarget(at: point)
    guard target == .nothing else { return target }
    if isNear(lifeProps?.bowl, point) { return .bowl }
    if isNear(toys.treatJar, point) { return .treats }
    return isOpenFloor(point) ? .floor : .nothing
  }

  /// Whether `point` is within a finger's reach of `entity` on screen.
  private func isNear(_ entity: Entity?, _ point: CGPoint) -> Bool {
    guard let entity, entity.isEnabled,
      let shown = camera.project(entity.position(relativeTo: room), in: viewSize)
    else { return false }
    return hypot(shown.x - point.x, shown.y - point.y) < Self.toyReach
  }

  /// Whether `point` is over the floor the cat walks on, not past its edge.
  func isOpenFloor(_ point: CGPoint) -> Bool {
    let size = SIMD2(Float(viewSize.width), Float(viewSize.height))
    guard
      let spot = NookiFloorRay.floorPoint(
        under: SIMD2(Float(point.x), Float(point.y)), viewSize: size, camera: camera.position,
        target: camera.target, verticalFieldOfView: camera.fieldOfView,
        height: layout.cat.spot.scene.y)
    else { return false }
    return simd_distance(layout.onCatSurface(spot), spot) < layout.cat.length * 0.2
  }

  // MARK: - Food

  /// A tap on the bowl fills it. The cat trots over and eats, unless it has only just eaten.
  func fillBowl() -> [PetSceneEvent] {
    toys.mealStart = nil
    lifeProps?.show(meal: 1)
    purr.feel(.nudge)
    guard let bowl = lifeProps?.bowl.position(relativeTo: room),
      let response = hands.play.handle(.bowlFilled, at: clock), isFreeToPlay
    else { return [] }
    let at = SIMD2(bowl.x, bowl.z)
    let from = catSpot
    switch response.reaction {
    case .eat:
      let front = layout.onCatSurface(
        CatTrip.towards(at, from: from, upTo: 10, keep: layout.cat.length * 0.42))
      cancelPlay()
      let eating = 4.0
      trip = CatTrip(
        from: from, heading: bodyHeading,
        legs: [
          .hold(behaviour.playable(.perk), seconds: 0.5, facing: at),
          .walk(to: front, speed: walkSpeed * 1.5),
          .hold(behaviour.playable(.eat), seconds: eating, facing: at),
          .hold(behaviour.playable(.happy), seconds: 1.2, facing: at),
          .walk(to: home, speed: walkSpeed),
          .hold(behaviour.playable(.sit), seconds: 0.5, facing: homeFront),
        ], at: clock)
      tripKind = .wander
      toys.mealStart = clock + 0.5 + Double(simd_distance(from, front) / (walkSpeed * 1.5)) + 0.3
      toys.mealLength = eating
    default:
      headLook(at: bowl, for: 1.5)
      behaviour.perform(.slowBlink, at: clock)
    }
    return show(response)
  }

  /// The food sinks while the cat eats, and stays where it got to.
  func stepMeal() {
    guard let start = toys.mealStart else { return }
    let eaten = min(max((clock - start) / toys.mealLength, 0), 1)
    lifeProps?.show(meal: Float(1 - 0.75 * eaten))
    if eaten >= 1 { toys.mealStart = nil }
  }

  // MARK: - A treat from the fingers

  /// The finger has a treat from the jar at `point`. Held out near the cat's nose, the cat
  /// sniffs and takes it.
  func offerTreat(at point: CGPoint) -> [PetSceneEvent] {
    guard let spot = floorUnder(point), let treat = toys.treat else { return [] }
    let length = layout.cat.length
    if toys.treatAt == nil {
      toys.treatTaken = false
      purr.feel(.lift)
    }
    toys.treatAt = spot
    if !toys.treatTaken {
      treat.isEnabled = true
      treat.position = floorPoint(spot, lift: length * 0.32)
      treat.orientation = simd_quatf(
        angle: Float(clock * 2).truncatingRemainder(dividingBy: 6.3) * 0.2, axis: [0, 1, 0])
      headLook(at: treat.position(relativeTo: nil), for: 0.6)
    }
    guard !toys.treatTaken, isFreeToPlay, simd_distance(spot, nose) < length * 0.75,
      let response = hands.play.handle(.treatHeldOut, at: clock)
    else { return [] }
    let at = spot
    cancelPlay()
    switch response.reaction {
    case .takeTreat:
      toys.treatTaken = true
      trip = CatTrip(
        from: catSpot, heading: bodyHeading,
        legs: [
          .hold(behaviour.playable(.sniff), seconds: 0.9, facing: at),
          .hold(behaviour.playable(.eat), seconds: 1.6, facing: at),
          .hold(behaviour.playable(.happy), seconds: 1.4),
        ], at: clock)
      tripKind = .wander
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(0.9))
        guard let self else { return }
        self.toys.treat?.isEnabled = false
        self.purr.feel(.chomp)
        self.purr.heart(at: self.screen.cat)
      }
      return show(CatPlayResponse(reaction: .takeTreat, need: response.need))
    default:
      trip = CatTrip(
        from: catSpot, heading: bodyHeading,
        legs: [
          .hold(behaviour.playable(.sniff), seconds: 0.8, facing: at),
          .hold(behaviour.playable(.tailFlick), seconds: 1.2, facing: homeFront),
        ], at: clock)
      tripKind = .wander
      return show(response)
    }
  }

  /// The finger lets go of the treat: one the cat did not take goes back in the jar.
  func endTreat() {
    toys.treatAt = nil
    if !toys.treatTaken { toys.treat?.isEnabled = false }
  }

  // MARK: - Held up and put down

  var isHoldingCat: Bool { toys.liftedAt != nil }

  /// A long press on the cat picks it up, its legs hanging. Not while it carries a note.
  func liftCat() -> Bool {
    guard hasCat, tripKind != .delivery, tripKind != .greeting, world.activity == .sleeping,
      opening == nil
    else { return false }
    let spot = catSpot
    cancelPlay()
    if trip != nil { endTrip() }
    toys.liftedAt = spot
    toys.liftedClock = clock
    if let response = hands.play.handle(.lifted, at: clock) { _ = show(response) }
    return true
  }

  func moveLifted(to point: CGPoint) {
    guard isHoldingCat, let spot = floorUnder(point) else { return }
    toys.liftedAt = spot
  }

  /// Puts the cat down under the finger, where it settles and stays until something calls it.
  func dropCat() {
    guard let spot = toys.liftedAt else { return }
    toys.liftedAt = nil
    // Put down on its own top, wherever it was picked up from.
    footing.level = layout.catHomeLevel
    brainBody.jump = nil
    brainBody.goalFor = nil
    let eye = SIMD2(camera.position.x, camera.position.z)
    perch = (layout.onCatSurface(spot), CatTrip.heading(from: spot, to: eye))
    let height = catHolder.position.y
    catHolder.position = homeScene
    if height > homeScene.y { dropped = (height, clock) }
    if let response = hands.play.handle(.placed, at: clock) { _ = show(response) }
    behaviour.perform(.knead, for: 2.4, at: clock)
    updateScreen()
  }

  /// While held: hanging under the finger, swinging a little, facing the camera.
  func stepHeld() -> CatTrip.Pose? {
    guard let spot = toys.liftedAt else { return nil }
    let length = layout.cat.length
    let since = Float(clock - toys.liftedClock)
    let rise = min(since / 0.25, 1)
    let swing = sin(since * 3.4) * 0.09 * exp(-since * 0.4) * (reduceMotion ? 0 : 1)
    catHolder.position = floorPoint(spot, lift: length * 0.55 * rise)
    catHolder.position.x += swing * length * 0.3
    screen.cat = camera.project(catHolder.position + [0, length * 0.55, 0], in: viewSize)
    let eye = SIMD2(camera.position.x, camera.position.z)
    let heading = CatTrip.heading(from: spot, to: eye)
    hands.leanGoal = swing * 1.5
    return CatTrip.Pose(
      spot: spot, heading: heading, action: behaviour.playable(.dangle), speed: 0, leg: 0,
      progress: 0, isDone: false)
  }

  // MARK: - Called and asked for a trick

  /// A double tap on the floor calls the cat there. A tired cat only looks.
  func callCat(to point: CGPoint) -> [PetSceneEvent] {
    guard isFreeToPlay, let under = floorUnder(point),
      let response = hands.play.handle(.called, at: clock)
    else { return [] }
    switch response.reaction {
    case .come:
      cancelPlay()
      let from = catSpot
      // It stops as far short of the finger as its temperament keeps, and comes as far as it can
      // without walking through what stands on its top.
      let wanted = layout.onCatSurface(under)
      let keep = Float(brainBody.frame?.personalSpace ?? 0) * layout.cat.length * 1.5
      let gap = wanted - from
      let distance = simd_length(gap)
      let near = distance > keep ? wanted - gap / distance * keep : from
      let spot = layout.catReach(from: from, to: near)
      if trip != nil { endTrip() }
      let eye = SIMD2(camera.position.x, camera.position.z)
      perch = (spot, CatTrip.heading(from: spot, to: eye))
      trip = CatTrip(
        from: from, heading: bodyHeading,
        legs: [
          .hold(behaviour.playable(.perk), seconds: 0.4, facing: spot),
          .walk(to: spot, speed: walkSpeed * 1.3),
          .hold(behaviour.playable(.sit), seconds: 0.6, facing: eye),
        ], at: clock)
      tripKind = .wander
    default:
      headLook(at: floorPoint(under), for: 1.4)
      behaviour.perform(.slowBlink, at: clock)
    }
    return show(response)
  }

  /// A double tap on the cat asks for a trick: it sits up, waves, spins round, or gives a
  /// high-five once it has learned one. On the desk or the cardigan it is a shoo instead.
  func askTrick() -> [PetSceneEvent] {
    if let step = brainBody.frame?.stack.step, CatUpbringing.shooable.contains(step) {
      behaviour.perform(.perk, at: clock)
      return [.shooed]
    }
    guard isFreeToPlay, let response = hands.play.handle(.trickAsked, at: clock) else { return [] }
    switch response.reaction {
    case .trick(let trick):
      let from = catSpot
      let eye = SIMD2(camera.position.x, camera.position.z)
      if trip != nil { endTrip() }
      let legs: [CatTrip.Leg]
      switch trick {
      case .sit:
        legs = [
          .hold(behaviour.playable(.sit), seconds: 1.4, facing: eye),
          .hold(behaviour.playable(.slowBlink), seconds: 1.2, facing: eye),
        ]
      case .wave:
        legs = [
          .hold(behaviour.playable(.sit), seconds: 0.4, facing: eye),
          .hold(behaviour.playable(.wave), seconds: 1.6, facing: eye),
          .hold(behaviour.playable(.happy), seconds: 0.8, facing: eye),
        ]
      case .highFive:
        legs = [
          .hold(behaviour.playable(.sit), seconds: 0.3, facing: eye),
          .hold(behaviour.playable(.reachUp), seconds: 1.2, facing: eye),
          .hold(behaviour.playable(.happy), seconds: 0.9, facing: eye),
        ]
      case .spin:
        let facing = CatTrip.heading(from: from, to: eye)
        let round = (1...4).map { step -> CatTrip.Leg in
          let turn = facing + Float(step) * .pi / 2
          return .hold(
            behaviour.playable(.idle), seconds: 0.32,
            facing: from + SIMD2(-sin(turn), -cos(turn)))
        }
        legs = round + [.hold(behaviour.playable(.happy), seconds: 1.0, facing: eye)]
      }
      trip = CatTrip(from: from, heading: bodyHeading, legs: legs, at: clock)
      tripKind = .wander
      purr.heart(at: screen.cat)
    default:
      behaviour.perform(.slowBlink, at: clock)
    }
    return show(response)
  }

  // MARK: - Helpers

  /// Where the cat is on the floor now.
  var catSpot: SIMD2<Float> { SIMD2(catHolder.position.x, catHolder.position.z) }

  /// Just in front of the cat's face, for holding a treat to.
  private var nose: SIMD2<Float> {
    catSpot + SIMD2(-sin(bodyHeading), -cos(bodyHeading)) * layout.cat.length * 0.45
  }

  /// Whether the cat can be asked to do something now: not carrying a note, greeting, opening
  /// the room or being held.
  var isFreeToPlay: Bool {
    hasCat && world.activity == .sleeping && opening == nil && tripKind != .delivery
      && tripKind != .greeting && !isHoldingCat && footing.level == layout.catHomeLevel
      && brainBody.jump == nil
  }

  /// Ends a game in progress, leaving the cat where it is.
  func cancelPlay() {
    toys.pursuit = nil
  }
}
