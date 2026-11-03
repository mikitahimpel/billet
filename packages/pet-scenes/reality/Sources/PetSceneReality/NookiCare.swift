import CoreGraphics
import Foundation
import Pet
import PetScene
import RealityKit
import simd

/// Food, treats, being picked up and put down, being called and doing tricks, in Nooki.
extension NookiDiorama {
  // MARK: - Building

  func buildTreat() {
    let treat = GenzRoom.treatModel(length: Self.catReach)
    treat.isEnabled = false
    room.addChild(treat)
    toys.treat = treat
  }

  // MARK: - Where a tap lands

  private var screenSize: CGSize {
    CGSize(width: CGFloat(fittedSize.x), height: CGFloat(fittedSize.y))
  }

  private func shown(_ point: SIMD3<Float>) -> CGPoint? {
    GenzCamera.project(
      point, from: camera.position, towards: NookiCamera.target, fieldOfView: Self.fieldOfView,
      in: screenSize)
  }

  /// What a finger at `point` is on, for the cat's own touches: the cat, its toys, its bowl, or
  /// the open floor. Anything else is the room's.
  func tapTarget(at point: CGPoint) -> CatTouchTarget {
    if let body = catBody(), body.contains(SIMD2(Double(point.x), Double(point.y))) {
      return .cat
    }
    if let toy = toyTarget(at: point) { return .toy(toy) }
    if let bowl = shown(Self.bowlPosition + [0, 0.03, 0]),
      hypot(bowl.x - point.x, bowl.y - point.y) < GenzRoom.toyReach
    {
      return .bowl
    }
    return floorSpot(under: point) != nil ? .floor : .nothing
  }

  /// The open floor under `point`, or nil off the rug's edges.
  func floorSpot(under point: CGPoint) -> SIMD2<Float>? {
    guard
      let spot = NookiFloorRay.floorPoint(
        under: SIMD2(Float(point.x), Float(point.y)), viewSize: fittedSize,
        camera: camera.position, target: NookiCamera.target, verticalFieldOfView: Self.fieldOfView)
    else { return nil }
    let low = NookiFloorPlan.floorMin + 0.08
    let high = NookiFloorPlan.floorMax - 0.08
    guard spot.x >= low.x, spot.y >= low.y, spot.x <= high.x, spot.y <= high.y else { return nil }
    return spot
  }

  // MARK: - Food

  var catSpot: SIMD2<Float> {
    let at = catHolder.position(relativeTo: room)
    return SIMD2(at.x, at.z)
  }

  private var catHeading: Float {
    let forward = catHolder.orientation(relativeTo: room).act([0, 0, -1])
    return atan2(-forward.x, -forward.z)
  }

  private var bed: SIMD2<Float> { SIMD2(Self.bedSpot.x, Self.bedSpot.z) }

  var isFreeToPlay: Bool {
    hasCat && world.activity == .sleeping && opening == nil && !noteIsOpen
      && !yarnPlay.isPlaying && toys.liftedAt == nil
  }

  /// A tap on the bowl fills it: the cat hops down, trots over and eats, unless it has just
  /// eaten.
  func fillBowl() -> [PetSceneEvent] {
    toys.meal = 1
    toys.mealStart = nil
    purr.feel(.nudge)
    guard isFreeToPlay, let response = hands.play.handle(.bowlFilled, at: clock) else { return [] }
    let bowl = SIMD2(Self.bowlPosition.x, Self.bowlPosition.z)
    switch response.reaction {
    case .eat:
      toys.pursuit = nil
      let from = catSpot
      let front = CatTrip.towards(bowl, from: from, upTo: 10, keep: 0.11)
      let eating = 4.0
      trip = CatTrip(
        from: from, heading: catHeading,
        legs: [
          .hold(behaviour.playable(.perk), seconds: 0.5, facing: bowl),
          .walk(to: front, speed: Self.walkPace * 1.5),
          .hold(behaviour.playable(.eat), seconds: eating, facing: bowl),
          .hold(behaviour.playable(.happy), seconds: 1.2, facing: bowl),
          .walk(to: bed, speed: Self.walkPace),
          .hold(behaviour.playable(.sit), seconds: 0.5),
        ], at: clock)
      toys.mealStart =
        clock + 0.5 + Double(simd_distance(from, front) / (Self.walkPace * 1.5)) + 0.3
      toys.mealLength = eating
    default:
      headLook(at: Self.bowlPosition, for: 1.5)
      behaviour.perform(.slowBlink, at: clock)
    }
    return show(response)
  }

  /// The food sinks while the cat eats.
  func stepMeal() {
    guard let start = toys.mealStart else { return }
    let eaten = min(max((clock - start) / toys.mealLength, 0), 1)
    toys.meal = Float(1 - 0.75 * eaten)
    if eaten >= 1 { toys.mealStart = nil }
  }

  // MARK: - A treat from the fingers

  /// A treat between the fingers at `point`, held out to the cat: near its nose, it sniffs and
  /// takes it. Nooki keeps its treats in the bowl, so a drag from the bowl brings one out.
  func offerTreat(at point: CGPoint) -> [PetSceneEvent] {
    guard let treat = toys.treat,
      let spot = NookiFloorRay.floorPoint(
        under: SIMD2(Float(point.x), Float(point.y)), viewSize: fittedSize,
        camera: camera.position, target: NookiCamera.target,
        verticalFieldOfView: Self.fieldOfView, height: 0.18)
    else { return [] }
    if toys.treatAt == nil {
      toys.treatTaken = false
      purr.feel(.lift)
    }
    toys.treatAt = spot
    if !toys.treatTaken {
      treat.isEnabled = true
      treat.position = SIMD3(spot.x, 0.18, spot.y)
      headLook(at: treat.position(relativeTo: nil), for: 0.6)
    }
    let nose = catSpot + SIMD2(-sin(catHeading), -cos(catHeading)) * Self.catReach * 0.45
    guard !toys.treatTaken, isFreeToPlay, trip == nil,
      simd_distance(spot, nose) < Self.catReach * 0.8,
      let response = hands.play.handle(.treatHeldOut, at: clock)
    else { return [] }
    toys.pursuit = nil
    switch response.reaction {
    case .takeTreat:
      toys.treatTaken = true
      trip = CatTrip(
        from: catSpot, heading: catHeading,
        legs: [
          .hold(behaviour.playable(.sniff), seconds: 0.9, facing: spot),
          .hold(behaviour.playable(.eat), seconds: 1.6, facing: spot),
          .hold(behaviour.playable(.happy), seconds: 1.4),
        ], at: clock)
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(0.9))
        guard let self else { return }
        self.toys.treat?.isEnabled = false
        self.purr.feel(.chomp)
        self.purr.heart(at: self.catPointOnScreen)
      }
      return show(CatPlayResponse(reaction: .takeTreat, need: response.need))
    default:
      trip = CatTrip(
        from: catSpot, heading: catHeading,
        legs: [
          .hold(behaviour.playable(.sniff), seconds: 0.8, facing: spot),
          .hold(behaviour.playable(.tailFlick), seconds: 1.2),
        ], at: clock)
      return show(response)
    }
  }

  func endTreat() {
    toys.treatAt = nil
    if !toys.treatTaken { toys.treat?.isEnabled = false }
  }

  // MARK: - Held up and put down

  var isHoldingCat: Bool { toys.liftedAt != nil }

  func liftCat() -> Bool {
    guard isFreeToPlay, !renovation.isOn else { return false }
    toys.pursuit = nil
    trip = nil
    toys.liftedAt = catSpot
    toys.liftedClock = clock
    if let response = hands.play.handle(.lifted, at: clock) { _ = show(response) }
    return true
  }

  func moveLifted(to point: CGPoint) {
    guard isHoldingCat else { return }
    if let spot = NookiFloorRay.floorPoint(
      under: SIMD2(Float(point.x), Float(point.y)), viewSize: fittedSize,
      camera: camera.position, target: NookiCamera.target, verticalFieldOfView: Self.fieldOfView)
    {
      toys.liftedAt = simd_clamp(
        spot, NookiFloorPlan.floorMin + 0.08, NookiFloorPlan.floorMax - 0.08)
    }
  }

  /// Puts the cat down under the finger. Into the bed it curls up; on the rug it sits and stays
  /// a while, then goes back to bed.
  func dropCat() {
    guard let spot = toys.liftedAt else { return }
    toys.liftedAt = nil
    if let response = hands.play.handle(.placed, at: clock) { _ = show(response) }
    let eye = SIMD2(camera.position.x, camera.position.z)
    if simd_distance(spot, bed) < 0.14 {
      trip = CatTrip(
        from: spot, heading: catHeading,
        legs: [
          .walk(to: bed, speed: Self.walkPace),
          .hold(behaviour.playable(.knead), seconds: 2.4),
        ], at: clock)
    } else {
      stay(at: spot, facing: eye)
    }
  }

  /// Sits at `spot` for a good while, as if it chose it, then goes back to bed.
  private func stay(at spot: SIMD2<Float>, facing: SIMD2<Float>, from start: SIMD2<Float>? = nil) {
    var legs: [CatTrip.Leg] = []
    if let start, simd_distance(start, spot) > 0.01 {
      legs.append(.hold(behaviour.playable(.perk), seconds: 0.4, facing: spot))
      legs.append(.walk(to: spot, speed: Self.walkPace * 1.3))
    }
    legs += [
      .hold(behaviour.playable(.knead), seconds: 2.4, facing: facing),
      .hold(behaviour.playable(.sit), seconds: Self.stayLength, facing: facing),
      .walk(to: bed, speed: Self.walkPace),
      .hold(behaviour.playable(.sit), seconds: 0.5),
    ]
    trip = CatTrip(from: start ?? spot, heading: catHeading, legs: legs, at: clock)
  }

  /// How long the cat stays where it was put or called before going back to bed.
  static let stayLength = 30.0

  /// While held: hanging under the finger, swinging a little.
  func stepHeld() -> (CatTrip.Pose, SIMD3<Float>)? {
    guard let spot = toys.liftedAt else { return nil }
    let since = Float(clock - toys.liftedClock)
    let rise = min(since / 0.25, 1)
    let swing = sin(since * 3.4) * 0.09 * exp(-since * 0.4) * (reduceMotion ? 0 : 1)
    hands.leanGoal = swing * 1.5
    let eye = SIMD2(camera.position.x, camera.position.z)
    let pose = CatTrip.Pose(
      spot: spot, heading: CatTrip.heading(from: spot, to: eye),
      action: behaviour.playable(.dangle), speed: 0, leg: 0, progress: 0, isDone: false)
    return (pose, SIMD3(spot.x + swing * 0.1, 0.2 * rise, spot.y))
  }

  // MARK: - Called and asked for a trick

  func callCat(to point: CGPoint) -> [PetSceneEvent] {
    guard isFreeToPlay, let spot = floorSpot(under: point),
      let response = hands.play.handle(.called, at: clock)
    else { return [] }
    switch response.reaction {
    case .come:
      toys.pursuit = nil
      let from = catSpot
      trip = nil
      stay(at: spot, facing: SIMD2(camera.position.x, camera.position.z), from: from)
    default:
      headLook(at: SIMD3(spot.x, 0, spot.y), for: 1.4)
      behaviour.perform(.slowBlink, at: clock)
    }
    return show(response)
  }

  /// A double tap on the cat asks for a trick, or is a shoo when it sits where it should not.
  func askTrick() -> [PetSceneEvent] {
    if let step = brain?.stack.step, CatUpbringing.shooable.contains(step) {
      behaviour.perform(.perk, at: clock)
      return [.shooed]
    }
    guard isFreeToPlay, trip == nil, let response = hands.play.handle(.trickAsked, at: clock)
    else { return [] }
    switch response.reaction {
    case .trick(let trick):
      let from = catSpot
      let eye = SIMD2(camera.position.x, camera.position.z)
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
        legs =
          (1...4).map { step -> CatTrip.Leg in
            let turn = facing + Float(step) * .pi / 2
            return .hold(
              behaviour.playable(.idle), seconds: 0.32,
              facing: from + SIMD2(-sin(turn), -cos(turn)))
          } + [.hold(behaviour.playable(.happy), seconds: 1.0, facing: eye)]
      }
      trip = CatTrip(from: from, heading: catHeading, legs: legs, at: clock)
      purr.heart(at: catPointOnScreen)
    default:
      behaviour.perform(.slowBlink, at: clock)
    }
    return show(response)
  }
}
