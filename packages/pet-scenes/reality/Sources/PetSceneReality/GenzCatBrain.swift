import Foundation
import Pet
import RealityKit
import simd

/// What the styled room's cat does with a frame from its brain: where it is walking to, since when
/// it has been there, and the touch last told to the host.
struct CatBrainBody {
  var frame: CatBrainFrame?
  /// How many times faster than real time the brain's clock runs. Above 1 the body jumps to each
  /// place instead of walking there, so a fast day reads as a time-lapse.
  var speed = 1.0
  /// Where the current frame sends the cat, and how high it sits there.
  var goal: SIMD2<Float>?
  var lift: Float = 0
  /// The room clock when the cat got to `goal`, or nil while it is on its way.
  var arrived: Double?
  /// The step and its start the goal was worked out for, and the step before it.
  var goalFor: (CatActivityStep, Double)?
  var cameFrom: CatActivityStep?
  var told: CatInteraction?
  var toldRoom: RoomAffordances?
  var toldWeather: ViewWeather?
  /// When each piece was moved while decorating, for a cat to inspect.
  var moved: [String: Double] = [:]
  /// The room's affordances where they stand, worked out again when a step starts or the room
  /// changes, so a frame reads them without making anything.
  var places: [GenzAffordance] = []
  /// A step from the window's spot out through the glass.
  var outward = SIMD2<Float>.zero
}

/// One affordance of the styled room, with where it stands.
struct GenzAffordance {
  var affordance: RoomAffordance
  var spot: SIMD2<Float>
  var height: Float
}

extension GenzRoom {
  /// Lets the brain drive the cat, or gives it back to the clip picker for nil.
  func followBrain(_ frame: CatBrainFrame?, speed: Double) {
    brainBody.speed = speed
    guard frame != brainBody.frame else { return }
    let before = brainBody.frame
    brainBody.frame = frame
    // Play chose a chase: the cat goes after the lamp's dot of light once it is free. Any other
    // step lets a chase that never started go.
    let step = frame?.stack.step
    let isNew = step != before?.stack.step || frame?.stepStart != before?.stepStart
    if isNew { chaseWanted = step == .chase || step == .zoomies }
  }

  /// The affordance kind of a piece, or nil for one the cat has no use for.
  static func affordanceKind(_ kind: GenzPiece.Kind) -> RoomAffordance.Kind? {
    switch kind {
    case .platformBed, .daybed, .quiltedDaybed, .quiltedBed, .catBed: .bed
    case .milkCrate, .bookCrate: .box
    case .bookshelf, .wallShelves: .shelf
    case .hoodiePile, .chairWithClothes, .cardigan: .soft
    case .mugs, .phoneOnCharger, .candles: .smallItem
    case .checkeredRug, .roundRug, .patternRug: .rug
    case .cubeNightstand, .sunsetLamp, .sneakers, .monstera, .posterFrame, .bookStack,
      .thriftLamp, .snakePlant, .pleatedLamp, .leafyPlant, .polaroids, .recordPlayer, .speaker,
      .windowBench, .sideTable, .knitPouf, .stringLights:
      nil
    }
  }

  /// What the room offers the cat now: its pieces where they stand, the window, the bowl and the
  /// toys. Something on the top the cat lives on is in reach; the rest can be looked at.
  func affordances() -> [GenzAffordance] {
    var out: [GenzAffordance] = []
    let catHeight = layout.cat.spot.scene.y
    let surface = layout.catSurface
    func onTop(_ spot: SIMD2<Float>, _ height: Float) -> Bool {
      guard let surface else { return abs(height - catHeight) < 0.15 }
      let margin = layout.cat.length * 0.2
      return abs(height - catHeight) < 0.15 && spot.x >= surface.min.x - margin
        && spot.x <= surface.max.x + margin && spot.y >= surface.min.y - margin
        && spot.y <= surface.max.y + margin
    }
    for (index, placement) in layout.pieces.enumerated() {
      guard let kind = Self.affordanceKind(placement.piece.kind) else { continue }
      let name = Self.decorName(placement, index: index)
      let at =
        pieceHolders.indices.contains(index)
        ? pieceHolders[index].position(relativeTo: room) : placement.centre.scene
      let spot = SIMD2(at.x, at.z)
      // The piece the cat lives on is in reach where the cat is.
      let carries =
        surface.map { spot == simd_clamp(spot, $0.min, $0.max) } ?? false
        && placement.piece.kind.size.z > layout.cat.spot.z * 0.5 && at.y < catHeight
      let reachable = carries || onTop(spot, at.y)
      out.append(
        GenzAffordance(
          affordance: RoomAffordance(
            id: name, kind: kind, reachable: reachable, since: brainBody.moved[name]),
          spot: carries ? home : spot, height: carries ? catHeight : at.y))
    }
    if !layout.window.isEmpty {
      let xs = layout.window.map(\.x)
      let ys = layout.window.map(\.y)
      let middle = SIMD2((xs.min()! + xs.max()!) / 2, (ys.min()! + ys.max()!) / 2)
      let near = layout.onCatSurface(middle)
      out.append(
        GenzAffordance(
          affordance: RoomAffordance(
            id: "window", kind: .window,
            reachable: simd_distance(near, middle) < layout.cat.length * 1.5),
          spot: near, height: catHeight))
    }
    if let bowl = lifeProps?.bowl.position(relativeTo: room) {
      out.append(
        GenzAffordance(
          affordance: RoomAffordance(id: "bowl", kind: .bowl), spot: SIMD2(bowl.x, bowl.z),
          height: catHeight))
    }
    if let yarn = toyPlace(.yarn) ?? toyPlace(.ball) {
      out.append(
        GenzAffordance(
          affordance: RoomAffordance(id: "toy", kind: .toy), spot: yarn, height: catHeight))
    }
    return out
  }

  /// Tells the host what the room offers when that changes: once built, after decorating, and
  /// when the view outside changes its weather.
  func reportAffordances() {
    guard isBuilt else { return }
    refreshPlaces()
    let room = RoomAffordances(brainBody.places.map(\.affordance))
    let weather = screen.windowView.shownWeather
    guard room != brainBody.toldRoom || weather != brainBody.toldWeather else { return }
    brainBody.toldRoom = room
    brainBody.toldWeather = weather
    report?(.affordances(room, weather: weather))
  }

  /// A piece was moved while decorating: something new for the cat to look at.
  func pieceMoved(_ name: String) {
    brainBody.moved[name] = Date().timeIntervalSince1970
    reportAffordances()
  }

  /// What a person is doing with the cat right now, as this phone's touch shows it.
  var liveInteraction: CatInteraction? {
    if toys.liftedAt != nil { return .held }
    if let pursuit = toys.pursuit { return .toy(pursuit.toy) }
    if toys.mealStart != nil { return .fed }
    if petClock != nil { return .petted(hands.isOnBack(at: clock) ? .belly : .back) }
    if tripKind == .greeting, trip != nil { return .greeting }
    if clock - lastBat < Self.battingFor { return .batting }
    if tripKind == .wander, perch != nil, trip != nil { return .called }
    if gazePoint != nil, clock <= gazeUntil, !watchingView { return .followFinger }
    return nil
  }

  /// How long a bat shows as the brain's Batting interaction, in seconds.
  static let battingFor = 1.2

  /// Tells the host when this phone's touch changes, for the brain's interaction region.
  func reportTouch() {
    guard brainBody.frame != nil else { return }
    let now = liveInteraction
    guard now != brainBody.told else { return }
    brainBody.told = now
    report?(.touching(now))
  }

  // MARK: - The body

  /// The pose the brain asks for this frame, or nil when it is off. Walks the cat to where its
  /// step wants it, then plays the step's clip there, with a reflex now and then in a calm one.
  func stepBrain(_ step: Float) -> CatTrip.Pose? {
    guard let frame = brainBody.frame, rig != nil else { return nil }
    let key = (frame.stack.step, frame.stepStart)
    if brainBody.goalFor.map({ $0 != key }) ?? true {
      brainBody.cameFrom = brainBody.goalFor?.0
      brainBody.goalFor = key
      refreshPlaces()
      let (goal, lift) = resolve(frame.target)
      brainBody.goal = goal
      brainBody.lift = lift
      brainBody.arrived = nil
    }
    let at = catSpot
    let goal = brainBody.goal ?? at
    let height = layout.cat.spot.scene.y + brainBody.lift
    let gap = goal - at
    let distance = simd_length(gap)
    if distance > layout.cat.length * 0.04, frame.stack.interaction == nil {
      // A gallop at the run clip's own speed keeps its paws planted; without one, a fast walk.
      // A lively temperament moves quicker, and its clip plays quicker to keep the paws planted.
      let gallops = frame.pace > 0.5 && behaviour.has(.run)
      let speed =
        (gallops
          ? galloping : frame.pace > 0.5 ? runSpeed : frame.pace > 0 ? walkSpeed * 1.4 : walkSpeed)
        * Float(frame.tempo)
      let next =
        brainBody.speed > 1 || reduceMotion
        ? goal : at + gap / distance * min(speed * step, distance)
      catHolder.position = SIMD3(
        next.x,
        catHolder.position.y + (height - catHolder.position.y)
          * min(step * 6, 1),
        next.y)
      screen.cat = camera.project(
        catHolder.position + [0, layout.cat.length * 0.55, 0], in: viewSize)
      return CatTrip.Pose(
        spot: next, heading: CatTrip.heading(from: at, to: goal), action: gallops ? .run : .walk,
        speed: speed,
        leg: 0, progress: 0, isDone: false)
    }
    if brainBody.arrived == nil {
      brainBody.arrived = clock
      catHolder.position.y = height
      // Trips, games and calls start from here and come back here.
      perch = (at, headingFor(frame) ?? bodyHeading)
      updateScreen()
    }
    let since = clock - (brainBody.arrived ?? clock)
    let reflex = CatReflexes.at(clock, seed: Self.reflexSeed, vitality: frame.stack.vitality)
    // A skeleton with the reflex joints blinks and flicks over any clip, as big as its
    // temperament moves; one without gets the reflex as a one-shot clip in a calm step.
    let layered = rig?.hasReflexes ?? false
    if layered {
      rig?.reflex(
        blink: reflex.blink ? 1 : 0, earTwitch: reflex.earTwitch ? 1 : 0,
        tailFlick: reflex.tailFlick ? 1 : 0, breath: Float(reflex.breath),
        strength: reduceMotion ? 0 : Float(frame.amplitude))
    }
    let action =
      frame.stack.interaction == nil
      ? lyingDown(frame, since: since)
        ?? (layered ? nil : reflex.oneShot(during: frame.stack.step)).flatMap {
          behaviour.has($0) ? $0 : nil
        }
        ?? cycled(frame.action, since: since) : behaviour.playable(frame.action)
    return CatTrip.Pose(
      spot: at, heading: headingFor(frame) ?? bodyHeading, action: action, speed: 0, leg: 0,
      progress: 0, isDone: false)
  }

  /// Lying down into a nap from standing or kneading, before the sleep loop takes over. A nap
  /// that only renews, or one already under way when the scene opened, goes straight to sleep.
  private func lyingDown(_ frame: CatBrainFrame, since: Double) -> CatAction? {
    guard frame.stack.step == .curl, let before = brainBody.cameFrom, before != .curl,
      behaviour.has(.lieDown), let info = rig?.info[.lieDown], since < info.duration
    else { return nil }
    return .lieDown
  }

  /// A one-shot clip played again and again through a long step, resting in its base pose
  /// between, so a long groom keeps grooming instead of freezing on its last frame.
  private func cycled(_ wanted: CatAction, since: Double) -> CatAction {
    let action = behaviour.playable(wanted)
    guard let info = rig?.info[action], !info.loops, info.duration > 0 else { return action }
    let base: CatAction =
      switch info.base {
      case .sit: behaviour.playable(.sit)
      case .stand: behaviour.playable(.idle)
      case .sleep: behaviour.playable(.sleep)
      case .loaf: behaviour.playable(.loaf)
      }
    let repeats = Self.repeating.contains(wanted)
    let period = info.duration + Self.restBetween
    if !repeats { return since < info.duration ? action : base }
    return since.truncatingRemainder(dividingBy: period) < info.duration ? action : base
  }

  /// The reflexes only need to look random, not to agree with the partner's phone.
  static let reflexSeed: UInt64 = 0xB1E7_CA75

  /// Clips a step keeps doing for as long as it lasts.
  static let repeating: Set<CatAction> = [.groom, .knead, .eat, .bat, .crouchWiggle, .sniff]
  static let restBetween = 0.6

  /// Which way the cat faces for `frame` once it is there.
  private func headingFor(_ frame: CatBrainFrame) -> Float? {
    let eye = SIMD2(camera.position.x, camera.position.z)
    switch frame.gaze {
    case .camera: return CatTrip.heading(from: catSpot, to: eye)
    case .window:
      guard let window = affordanceSpot(.window) else { return nil }
      return CatTrip.heading(from: catSpot, to: window + brainBody.outward)
    case .affordance(let kind):
      guard let spot = affordanceSpot(kind), simd_distance(spot, catSpot) > 0.05 else {
        return nil
      }
      return CatTrip.heading(from: catSpot, to: spot)
    case .ahead, .around: return nil
    }
  }

  private func refreshPlaces() {
    brainBody.places = affordances()
    guard let first = layout.window.first, let last = layout.window.dropFirst(2).first else {
      brainBody.outward = .zero
      return
    }
    let glass = SIMD2((first.x + last.x) / 2, (first.y + last.y) / 2)
    let out = glass - layout.onCatSurface(glass)
    let length = simd_length(out)
    brainBody.outward =
      length > 0.001 ? out / length * layout.cat.length * 3 : [0, -layout.cat.length * 3]
  }

  /// Where the head looks for the brain's gaze, and how freely, when no finger has it.
  func brainGaze() -> (point: SIMD3<Float>, weight: Float)? {
    guard let frame = brainBody.frame, brainBody.arrived != nil else { return nil }
    let head = catHolder.position(relativeTo: nil) + [0, layout.cat.length * 0.5, 0]
    switch frame.gaze {
    case .camera: return (camera.position, 0.9)
    case .window:
      guard let first = layout.window.first, let last = layout.window.dropFirst(2).first else {
        return nil
      }
      let middle = SIMD3((first.x + last.x) / 2, (first.z + last.z) / 2, (first.y + last.y) / 2)
      let out = SIMD3(brainBody.outward.x, 0, brainBody.outward.y) * 2
      return (room.convert(position: middle + out, to: nil), 0.8)
    case .affordance(let kind):
      guard let spot = affordanceSpot(kind) else { return nil }
      return (room.convert(position: SIMD3(spot.x, layout.cat.spot.scene.y, spot.y), to: nil), 0.7)
    case .around(let angle):
      // Looks round: the head sweeps from one side to the other over a few seconds.
      let sweep = Float(angle) * sin(Float(clock) * 0.7)
      let heading = bodyHeading + sweep
      let ahead = SIMD3(-sin(heading), 0.15, -cos(heading)) * layout.cat.length * 3
      return (head + ahead, 0.9)
    case .ahead: return nil
    }
  }

  /// The spot of the first affordance of `kind`.
  func affordanceSpot(_ kind: RoomAffordance.Kind) -> SIMD2<Float>? {
    place(kind)?.spot
  }

  /// The first place of `kind`, one in reach before one out of it.
  private func place(_ kind: RoomAffordance.Kind) -> GenzAffordance? {
    brainBody.places.first { $0.affordance.kind == kind && $0.affordance.reachable }
      ?? brainBody.places.first { $0.affordance.kind == kind }
  }

  /// Where on its top the cat goes for `target`, and how far above the top it sits there.
  private func resolve(_ target: CatTarget) -> (SIMD2<Float>, Float) {
    switch target {
    case .stay: return (catSpot, brainBody.lift)
    case .home:
      return (layout.onCatSurface(SIMD2(layout.cat.spot.scene.x, layout.cat.spot.scene.z)), 0)
    case .camera:
      let eye = SIMD2(camera.position.x, camera.position.z)
      return (
        layout.onCatSurface(CatTrip.towards(eye, from: catSpot, upTo: layout.cat.length * 1.2)), 0
      )
    case .roam(let a, let b):
      guard let surface = layout.catSurface else {
        let reach = layout.cat.length * 1.5
        return (layout.onCatSurface(home + SIMD2(Float(a - 0.5), Float(b - 0.5)) * reach * 2), 0)
      }
      let point = surface.min + (surface.max - surface.min) * SIMD2(Float(a), Float(b))
      return (layout.onCatSurface(point), 0)
    case .affordance(let kind):
      guard let found = place(kind) else { return (catSpot, 0) }
      switch kind {
      case .soft where found.affordance.reachable:
        // Into the cardigan itself, sunk into it a little.
        let surface = layout.catSurface
        let spot = surface.map { simd_clamp(found.spot, $0.min, $0.max) } ?? found.spot
        return (spot, layout.cat.length * 0.08)
      case .smallItem, .bowl, .toy:
        // Beside it, facing it.
        return (
          layout.onCatSurface(
            CatTrip.towards(found.spot, from: catSpot, upTo: 10, keep: layout.cat.length * 0.42)),
          0
        )
      default:
        return (layout.onCatSurface(found.spot), 0)
      }
    }
  }
}
