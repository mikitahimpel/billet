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
  /// Where the current frame sends the cat, and the way there round what stands on its top.
  var goal: SIMD2<Float>?
  var route: [SIMD2<Float>] = []
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
  /// The room clock when the step last made its sound, or nil before it has.
  var spoke: Double?
  /// Something a tantrum knocked off the seat, falling or gone until it is put back.
  var knock: CatKnock?
}

/// A piece the cat batted off the seat: where it stood, and since when it has been falling.
struct CatKnock {
  let holder: Entity
  let position: SIMD3<Float>
  let orientation: simd_quatf
  let away: SIMD2<Float>
  let start: Double
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
    hands.play.learned = frame?.tricks ?? []
    purr.brainPurring = frame?.purring ?? false
    // Care ended a need: hearts, and a happy buzz.
    if let was = before?.feeling, let now = frame?.feeling, was.isNeedy, !now.isNeedy {
      for _ in 0..<3 { purr.heart(at: screen.cat) }
      purr.feel(.trick)
      say.clear()
    }
    // Play chose a chase: the cat goes after the lamp's dot of light once it is free. Any other
    // step lets a chase that never started go.
    let step = frame?.stack.step
    let isNew = step != before?.stack.step || frame?.stepStart != before?.stepStart
    if isNew { chaseWanted = step == .chase || step == .zoomies }
  }

  /// The affordance kind of a piece, or nil for one the cat has no use for.
  static func affordanceKind(_ kind: GenzPiece.Kind) -> RoomAffordance.Kind? {
    switch kind {
    case .daybed, .quiltedDaybed, .catBed: .bed
    case .milkCrate, .bookCrate: .box
    case .bookshelf, .wallShelves: .shelf
    case .cardigan: .soft
    case .mugs, .phoneOnCharger, .candles: .smallItem
    case .roundRug, .patternRug: .rug
    case .bookStack, .thriftLamp, .snakePlant, .pleatedLamp, .leafyPlant, .polaroids, .recordPlayer,
      .speaker, .windowBench, .sideTable, .knitPouf, .stringLights:
      nil
    case .idolBeanBag, .idolFloorLamp, .idolThrow, .idolMonstera, .idolCactus, .idolBooks,
      .idolRecordPlayer, .idolMugs, .idolStringLights, .idolRug, .idolCatBed, .idolDesk,
      .idolArmchair, .idolFloorCushionTerracotta, .idolFloorCushionSage, .idolWallShelf,
      .idolFrameCat, .idolFrameLandscape, .idolPosterMoon, .idolPosterPlants, .idolClock,
      .idolMirror, .idolFishTank, .idolCatTree, .idolScratchPost, .idolFiddleFig, .idolPothos,
      .idolSucculents, .idolGuitar, .idolTeaSet, .idolRadio, .idolGlobe, .idolLavaLamp,
      .idolNeonHeart, .idolBeanBagSage, .idolBeanBagTerracotta, .idolYarnBasket:
      kind.idol?.affordance
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
            // In front of the pillows along the glass, it still looks out over them.
            reachable: simd_distance(near, middle) < layout.cat.length * 2.2),
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
      let goal = resolve(frame.target)
      brainBody.route = layout.catRoute(from: catSpot, to: goal)
      // Somewhere it cannot get to without going through something: as near as it gets.
      brainBody.goal = brainBody.route.last ?? catSpot
      brainBody.arrived = nil
      brainBody.spoke = nil
    }
    let at = catSpot
    let goal = brainBody.goal ?? at
    let near = layout.cat.length * 0.04
    while brainBody.route.count > 1, simd_distance(at, brainBody.route[0]) < near {
      brainBody.route.removeFirst()
    }
    let waypoint = brainBody.route.first ?? goal
    let gap = waypoint - at
    let distance = simd_length(gap)
    if simd_distance(at, goal) > near, frame.stack.interaction == nil {
      // A gallop at the run clip's own speed keeps its paws planted; without one, a fast walk.
      // A lively temperament moves quicker, and its clip plays quicker to keep the paws planted.
      let gallops = frame.pace > 0.5 && behaviour.has(.run)
      let speed =
        (gallops
          ? galloping : frame.pace > 0.5 ? runSpeed : frame.pace > 0 ? walkSpeed * 1.4 : walkSpeed)
        * Float(frame.tempo)
      let next =
        brainBody.speed > 1 || reduceMotion || distance < 1e-5
        ? goal : at + gap / distance * min(speed * step, distance)
      // Up onto the cardigan where it lies, down off it after.
      let height = layout.cat.spot.scene.y + layout.catStandHeight(at: next)
      catHolder.position = SIMD3(
        next.x,
        catHolder.position.y + (height - catHolder.position.y)
          * min(step * 6, 1),
        next.y)
      screen.cat = camera.project(
        catHolder.position + [0, layout.cat.length * 0.55, 0], in: viewSize)
      // Bringing a toy over, it carries it in its mouth.
      let carries = frame.stack.step == .dropToy && behaviour.has(.carry)
      return CatTrip.Pose(
        spot: next, heading: CatTrip.heading(from: at, to: distance < 1e-5 ? goal : waypoint),
        action: gallops ? .run : carries ? .carry : .walk,
        speed: speed,
        leg: 0, progress: 0, isDone: false)
    }
    let up = layout.catStandHeight(at: at)
    // Turned, if it must be, so its body keeps off the pillows beside it.
    let heading = layout.catHeading(at: at, want: headingFor(frame) ?? bodyHeading, height: up)
    if brainBody.arrived == nil {
      brainBody.arrived = clock
      catHolder.position.y = layout.cat.spot.scene.y + up
      // Trips, games and calls start from here and come back here.
      perch = (at, heading)
      updateScreen()
    }
    let since = clock - (brainBody.arrived ?? clock)
    speak(frame)
    stepKnock(frame, since: since)
    let reflex = CatReflexes.at(clock, seed: Self.reflexSeed, vitality: frame.stack.vitality)
    // Cross or sulking, the tail lashes.
    let lashing = Self.lashing.contains(frame.stack.step) && !reduceMotion
    // A skeleton with the reflex joints blinks and flicks over any clip, as big as its
    // temperament moves; one without gets the reflex as a one-shot clip in a calm step.
    let layered = rig?.hasReflexes ?? false
    if layered {
      rig?.reflex(
        blink: reflex.blink ? 1 : 0, earTwitch: reflex.earTwitch ? 1 : 0,
        tailFlick: lashing ? Float(0.5 + 0.5 * sin(clock * 7)) : reflex.tailFlick ? 1 : 0,
        breath: Float(reflex.breath),
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
      spot: at, heading: heading, action: action, speed: 0, leg: 0,
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

  /// Steps the tail lashes through.
  static let lashing: Set<CatActivityStep> = [.yowl, .flop, .knockOff, .sulk]

  /// Makes the step's sound once the cat is there, and again as often as the step says.
  private func speak(_ frame: CatBrainFrame) {
    guard let voice = frame.voice, frame.stack.interaction == nil else { return }
    if let last = brainBody.spoke {
      guard let every = frame.voiceEvery, clock - last >= every / max(frame.tempo, 0.5) else {
        return
      }
    }
    brainBody.spoke = clock
    sounds.play(voice, at: clock)
    say.say(voice, feeling: frame.feeling)
    if voice == .yowl { purr.feel(.settle) }
  }

  /// A tantrum bats the nearest small thing off the seat a second into the swipe. It slides,
  /// tips over the edge and falls out of sight, and is back where it stood a little later.
  private func stepKnock(_ frame: CatBrainFrame, since: Double) {
    if let knock = brainBody.knock {
      let u = Float(clock - knock.start)
      // Decorating puts it straight back, so the piece is where the person sees it.
      guard u < Self.knockGone, !decor.isOn else {
        knock.holder.position = knock.position
        knock.holder.orientation = knock.orientation
        knock.holder.isEnabled = true
        brainBody.knock = nil
        return
      }
      guard knock.holder.isEnabled else { return }
      let length = layout.cat.length
      let slide = min(u / 0.35, 1) * length * 0.35
      let fall = max(u - 0.35, 0)
      let drop = 4.9 * fall * fall
      let out = knock.away * (slide + fall * length * 0.8)
      knock.holder.position = knock.position + SIMD3(out.x, -drop, out.y)
      knock.holder.orientation =
        simd_quatf(
          angle: min(u * 5, 1.6), axis: simd_normalize(SIMD3(knock.away.y, 0, -knock.away.x)))
        * knock.orientation
      if drop > length * 4 { knock.holder.isEnabled = false }
      return
    }
    guard frame.stack.step == .knockOff, since > 1, !reduceMotion, !decor.isOn,
      let (holder, spot) = nearestSmallThing(),
      simd_distance(spot, catSpot) < layout.cat.length * 1.1
    else { return }
    let away = spot - catSpot
    let length = simd_length(away)
    brainBody.knock = CatKnock(
      holder: holder, position: holder.position, orientation: holder.orientation,
      away: length > 1e-4 ? away / length : [0, 1], start: clock)
    purr.feel(.pounce)
  }

  /// How long a knocked thing stays gone before it is back, in seconds.
  static let knockGone: Float = 25

  /// The holder of the small thing nearest the cat, and where it stands.
  private func nearestSmallThing() -> (Entity, SIMD2<Float>)? {
    var best: (Entity, SIMD2<Float>)?
    for (index, placement) in layout.pieces.enumerated()
    where Self.affordanceKind(placement.piece.kind) == .smallItem
      && pieceHolders.indices.contains(index)
    {
      let holder = pieceHolders[index]
      let at = holder.position(relativeTo: room)
      let spot = SIMD2(at.x, at.z)
      if best.map({ simd_distance($0.1, catSpot) > simd_distance(spot, catSpot) }) ?? true {
        best = (holder, spot)
      }
    }
    return best
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
    case .away: return CatTrip.heading(from: catSpot, to: catSpot * 2 - eye)
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
    case .away:
      let ahead = SIMD3(-sin(bodyHeading), -0.1, -cos(bodyHeading)) * layout.cat.length * 3
      return (head + ahead, 0.6)
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

  /// Where on its top the cat goes for `target`: clear of the pillows and what stands there, or
  /// up on the cardigan.
  func resolve(_ target: CatTarget) -> SIMD2<Float> {
    switch target {
    case .stay: return catSpot
    case .home:
      return layout.onCatSurface(SIMD2(layout.cat.spot.scene.x, layout.cat.spot.scene.z))
    case .camera:
      let eye = SIMD2(camera.position.x, camera.position.z)
      return layout.onCatSurface(
        CatTrip.towards(eye, from: catSpot, upTo: layout.cat.length * 1.2))
    case .roam(let a, let b):
      guard let surface = layout.catSurface else {
        let reach = layout.cat.length * 1.5
        return layout.onCatSurface(home + SIMD2(Float(a - 0.5), Float(b - 0.5)) * reach * 2)
      }
      return layout.onCatSurface(
        surface.min + (surface.max - surface.min) * SIMD2(Float(a), Float(b)))
    case .affordance(let kind):
      guard let found = place(kind) else { return catSpot }
      switch kind {
      case .soft where found.affordance.reachable:
        // Up on the cardigan, as near its middle as keeps off the pillows.
        let tops = layout.catObstacles.filter(\.sitOnTop)
        return tops.min {
          simd_distance($0.box.centre, found.spot) < simd_distance($1.box.centre, found.spot)
        }.map(layout.catSpotOnTop) ?? layout.onCatSurface(found.spot)
      case .smallItem, .bowl, .toy:
        // Beside it, facing it.
        return layout.onCatSurface(
          CatTrip.towards(found.spot, from: catSpot, upTo: 10, keep: layout.cat.length * 0.42))
      default:
        return layout.onCatSurface(found.spot)
      }
    }
  }
}
