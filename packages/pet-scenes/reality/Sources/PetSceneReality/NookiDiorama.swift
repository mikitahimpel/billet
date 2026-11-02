import CoreGraphics
import Foundation
import OSLog
import Pet
import PetScene
import RealityKit
import SwiftUI

/// The room and everything that moves in it. Metres, with the floor's top at y = 0 and the two
/// walls along x = -0.6 and z = -0.6.
@MainActor
final class NookiDiorama {
  let root = Entity()
  /// Called when the room has rendered in a view and a poster over it can go.
  var onReady: (() -> Void)?
  /// Called when Mochi is found to be missing, and again if a late load puts things right.
  var onMochiMissing: ((Bool) -> Void)?

  private let room = Entity()
  private let lens = PerspectiveCamera()
  private let mochi = Entity()
  private let note = Entity()
  private let bowlFill = Entity()
  private let streakMarks = Entity()
  private let lampLight = Entity()
  private let lanternLight = Entity()
  private let dust = Entity()
  private var holders: [NookiTarget: Entity] = [:]
  private var holderOrientations: [NookiTarget: simd_quatf] = [:]
  private var wobbles: [NookiTarget: Double] = [:]
  private var lampParts: [(model: ModelEntity, material: Int, glow: Float)] = []
  private var world = PetWorld()
  private var play = PetPlayState()
  private var clock = 0.0
  private var stepStart = 0.0
  private var petStart: Double?
  private var lookStart: Double?
  private var lookGoal: Float = 0
  private var lookTurn: Float = 0
  private var idleDelta = 0.0
  private(set) var isOnScreen = false
  private(set) var hasRehearsed = false
  private var isLoaded = false
  private(set) var loading: Task<Void, Never>?
  private(set) var mochiLoading: Task<Void, Never>?
  private(set) var isMochiMissing = false
  private var hasMochi = false
  private(set) var animator: NookiCatAnimator?
  private let missingMark = Entity()
  private let loadModel: NookiModelLoader
  private let loadShape: NookiModelLoader
  private let tiltSource: any NookiTiltSource
  private var tilt = NookiTilt()
  private let physics = NookiPhysics()
  private var flight = NookiPlaneFlight()
  private lazy var plane = NookiPaperPlane(paper: Self.clay(.paper))
  private var noteSheet: ModelEntity?
  private var noteMark: ModelEntity?
  let renovation: NookiRenovation
  private var yarnPlay = NookiYarnPlay(
    bed: NookiDiorama.bedSpot, floor: NookiDiorama.wallSpot.y,
    restHeading: NookiChoreography.restHeading)
  private var ballWas: SIMD3<Float>?
  private var ballSpeed: Float = 0
  private var lantern: Entity?
  private var shownDrawing: CGImage?
  /// The paper chosen so far. A drawing can arrive before the note is built.
  private var shownPaper: (material: PhysicallyBasedMaterial, hasDrawing: Bool)?
  /// The paint a tap puts on while the room is being changed.
  var paint = NookiSwatch.cream
  private var isFollowingTilt = false
  private let mochiDeadline: Duration
  private var settlingFrames = NookiDiorama.framesBeforeReady
  private var subscription: EventSubscription?
  private var camera = NookiCamera()
  private var tapTimer = NookiTapTimer()
  private var reduceMotion = false
  private var lampIsOn = true
  private var lampLevel: Float = 1
  private var noteIsOpen = false
  private var noteOpening: Float = 0
  private var bowlLevel: Float = 0

  nonisolated static let mochiScale: Float = 1.25
  static let missingMarkName = "mochi-missing"
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "NookiDiorama")

  private static let orbitPerPoint: Float = 0.006
  private static let idleStep = 1.0 / 30
  private static let framesBeforeReady = 4
  private static let rehearsalFrames = 8
  private static let lampIntensity: Float = 2600
  private static let lanternIntensity: Float = 500

  // Mochi lies in the bed in the middle of the rug, and hops to a spot under the wire.
  fileprivate static let bedSpot: SIMD3<Float> = [0.05, 0.095, 0.12]
  fileprivate static let wallSpot: SIMD3<Float> = [0.08, 0.012, -0.38]
  /// Share of the walk spent dropping from the bed to the floor.
  private static let bedDrop: Float = 0.25
  private static let carryHeight: Float = 0.34
  private static let noteHome: SIMD3<Float> = [0.08, 0.46, -0.565]
  private static let noteStart: SIMD3<Float> = [0.75, 1.05, -0.1]
  /// How far in front of the lens an opened note sits, and how much larger it gets.
  private static let noteReadingDistance: Float = 2.4
  private static let noteReadingScale: Float = 2
  static let yarnPosition: SIMD3<Float> = [0.36, 0, 0.54]
  private static let lookLimit: Float = 1
  /// How fast Mochi covers its walk to the wall, in metres a second.
  private static let walkPace: Float = 0.23
  private static let fieldOfView: Float = 30
  private static let noticeDistance: Float = 0.6
  private static let bowlPosition: SIMD3<Float> = [0.12, 0, 0.6]

  /// Starts empty and cheap, so a view can hold one before anything heavy has run.
  init(
    loadModel: NookiModelLoader? = nil,
    loadShape: NookiModelLoader? = nil,
    mochiDeadline: Duration = .seconds(12),
    tiltSource: any NookiTiltSource = NookiTiltSources.standard(),
    layoutStore: NookiLayoutStore = NookiLayoutStore(defaults: .standard)
  ) {
    renovation = NookiRenovation(store: layoutStore)
    let assets = NookiAssets()
    let bundled: NookiModelLoader = { name throws(NookiLoadError) in try await assets.model(name) }
    self.loadModel = loadModel ?? bundled
    self.loadShape = loadShape ?? bundled
    self.tiltSource = tiltSource
    self.mochiDeadline = mochiDeadline
    root.addChild(room)
    room.isEnabled = false
    lens.camera.fieldOfViewInDegrees = Self.fieldOfView
    root.addChild(lens)
    aimLens()
  }

  /// Builds the room once, a step at a time so the main actor keeps drawing. The work belongs to
  /// the diorama, not to the view that asked: a cover over the view cancels the view's tasks, and
  /// a cancelled load would leave a room with no lights or models and nothing to resume it. An
  /// asset that fails to load leaves a gap in the room and is logged. `onReady` follows once the
  /// room has rendered.
  func startLoading(priority: TaskPriority? = nil) {
    guard loading == nil else { return }
    loading = Task(priority: priority) { await load() }
  }

  /// Returns once the room is built.
  func untilLoaded() async {
    await loading?.value
  }

  private func load() async {
    NookiTrace.mark("load started")
    startLoadingMochi()
    let furniture = NookiFurniture.items.map { item in Task { await place(item) } }
    let environment = Task { await Self.ambientEnvironment() }
    await buildRoom()
    physics.buildShell(in: room)
    await buildBowl()
    await Task.yield()
    await buildNote()
    buildBackstop()
    mochi.position = Self.bedSpot
    mochi.name = NookiTarget.mochi.rawValue
    Self.makeTappable(mochi, size: [0.34, 0.26, 0.34], center: [0, 0.13, 0])
    room.addChild(mochi)
    for piece in furniture { await piece.value }
    NookiTrace.mark("furniture placed")
    findLampParts()
    await Task.yield()
    addLighting(environment: await environment.value)
    await Task.yield()
    buildDust()
    buildStreakMarks(play.streak)
    if let lantern { renovation.attach(lantern, to: NookiFurniture.tableName) }
    renovation.attach(lanternLight, to: NookiFurniture.tableName)
    renovation.attach(lampLight, to: NookiFurniture.lampName)
    renovation.applyStored()
    room.isEnabled = isOnScreen
    isLoaded = true
    NookiTrace.mark("room usable")
    updateTiltFollowing()
  }

  /// Shows the room in `content` for a few frames with nothing moving, then calls `done`.
  func startRehearsal(from content: RealityViewCameraContent, done: @escaping () -> Void) {
    room.isEnabled = true
    var frames = Self.rehearsalFrames
    subscription?.cancel()
    subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
      MainActor.assumeIsolated {
        frames -= 1
        guard frames == 0, let self else { return }
        self.subscription?.cancel()
        self.subscription = nil
        self.room.isEnabled = self.isOnScreen
        self.hasRehearsed = true
        NookiTrace.mark("room rehearsed")
        done()
      }
    }
  }

  /// How many entities the room holds so far.
  var entityCount: Int {
    var count = 0
    Self.visit(root) { _ in count += 1 }
    return count
  }

  /// Shows `world` from the start of its step.
  func show(_ world: PetWorld) {
    guard world != self.world else { return }
    self.world = world
    stepStart = clock
    if world.noteArrived {
      noteIsOpen = false
      flight = NookiPlaneFlight()
    }
    apply(elapsed: 0, delta: 0)
  }

  /// Puts the delivered drawing on the plane and the note, or plain paper if there is none.
  func show(drawing: CGImage?) {
    guard drawing !== shownDrawing else { return }
    shownDrawing = drawing
    guard let drawing else {
      applyPaper(Self.clay(.paper), hasDrawing: false)
      return
    }
    Task {
      let texture = try? await TextureResource(image: drawing, options: .init(semantic: .color))
      guard let texture, drawing === shownDrawing else { return }
      var paper = Self.clay(.paper)
      paper.baseColor = .init(tint: .white, texture: .init(texture))
      applyPaper(paper, hasDrawing: true)
    }
  }

  private func applyPaper(_ paper: PhysicallyBasedMaterial, hasDrawing: Bool) {
    shownPaper = (paper, hasDrawing)
    noteSheet?.model?.materials = [paper]
    noteMark?.isEnabled = !hasDrawing
    plane.setPaper(paper)
  }

  /// Whether the note wears a delivered drawing rather than its plain mark.
  var noteShowsDrawing: Bool { noteMark?.isEnabled == false }

  /// Shows the pair's play. A new pet from the partner gets the same reaction as a tap.
  func show(_ play: PetPlayState) {
    let petted = play.petsReceived > self.play.petsReceived
    self.play = play
    if petted { petStart = clock }
    if isLoaded, play.streak != streakMarks.children.count { buildStreakMarks(play.streak) }
  }

  /// Takes the room's updates from `content`. A diorama outlives its view, so each new view gets
  /// the updates, and its own settling before `onReady`.
  func startUpdates(from content: RealityViewCameraContent) {
    subscription?.cancel()
    hasRehearsed = true
    settlingFrames = Self.framesBeforeReady
    subscription = content.subscribe(
      to: SceneEvents.Update.self, on: nil, componentType: nil
    ) { [weak self] event in
      let delta = event.deltaTime
      MainActor.assumeIsolated {
        NookiTrace.frame { self?.tick(delta) }
      }
    }
  }

  func setReduceMotion(_ reduced: Bool) {
    reduceMotion = reduced
    dust.isEnabled = !reduced
    updateTiltFollowing()
  }

  /// Off screen, the room leaves the render and updates stop.
  func setOnScreen(_ onScreen: Bool) {
    isOnScreen = onScreen
    room.isEnabled = onScreen && isLoaded
    updateTiltFollowing()
  }

  private func updateTiltFollowing() {
    let follow = isOnScreen && isLoaded && !reduceMotion
    guard follow != isFollowingTilt else { return }
    isFollowingTilt = follow
    if follow { tiltSource.start() } else { tiltSource.stop() }
  }

  private func stepTilt(_ delta: Float) {
    if isFollowingTilt, let gravity = tiltSource.gravity {
      tilt.update(gravity: gravity, delta: delta)
    } else {
      tilt.settle(delta: delta)
    }
    guard tilt.lean != camera.lean else { return }
    camera.lean(to: tilt.lean)
    aimLens()
  }

  /// Reads the ball, moves the game on and passes the phone's lean to the ball.
  private func stepYarn(_ delta: Double) {
    guard physics.ball.parent != nil else { return }
    var at = physics.ball.position(relativeTo: room)
    if NookiPhysics.isLost(at) {
      physics.putBack(at: Self.yarnPosition)
      at = physics.ball.position(relativeTo: room)
    }
    if let ballWas, delta > 0 { ballSpeed = simd_distance(at, ballWas) / Float(delta) }
    ballWas = at
    yarnPlay.step(
      ball: NookiYarnPlay.Ball(position: SIMD2(at.x, at.z), speed: ballSpeed),
      delta: delta,
      canPlay: world.activity == .sleeping && !noteIsOpen,
      reduceMotion: reduceMotion)
    physics.setHeld(yarnPlay.holdsBall)
    physics.push(NookiPhysics.push(lean: tilt.pull, cameraYaw: camera.yaw))
  }

  /// Throws the ball, for a swipe ending at a screen velocity in points per second.
  func flickYarn(velocityX: Float, velocityY: Float) {
    physics.setVelocity(
      NookiPhysics.flick(screenVelocity: [velocityX, velocityY], cameraYaw: camera.yaw))
  }

  // MARK: - Changing the room

  func paintSurface(_ entity: Entity) {
    renovation.paint(entity, paint, reduceMotion: reduceMotion)
  }

  /// Lifts the piece under a finger, if there is one.
  func lift(_ entity: Entity) -> Bool {
    renovation.lift(entity)
  }

  /// Follows a finger at `point`, for a view of `size`, both in points.
  func moveLifted(to point: SIMD2<Float>, in size: SIMD2<Float>) {
    let floor = NookiFloorRay.floorPoint(
      under: point, viewSize: size, camera: camera.position, target: NookiCamera.target,
      verticalFieldOfView: Self.fieldOfView)
    if let floor { renovation.move(towards: floor) }
  }

  /// Sets a lifted piece down. Mochi looks up and stirs if it lands close by.
  func dropLifted() {
    guard let landed = renovation.drop() else { return }
    let bed = SIMD3(Self.bedSpot.x, 0, Self.bedSpot.z)
    guard simd_distance(SIMD3(landed.x, 0, landed.z), bed) < Self.noticeDistance else { return }
    look(at: landed)
    petStart = clock
  }

  func resetRoom() {
    renovation.reset(reduceMotion: reduceMotion)
  }

  // MARK: - Camera

  /// Follows a drag, in screen points since the last step.
  func orbit(byX deltaX: Float, y deltaY: Float) {
    camera.drag(yaw: -deltaX * Self.orbitPerPoint, pitch: deltaY * Self.orbitPerPoint)
    aimLens()
  }

  /// Lets go of a drag, with its velocity in points per second.
  func endOrbit(velocityX: Float, velocityY: Float) {
    camera.release(
      yawVelocity: -velocityX * Self.orbitPerPoint,
      pitchVelocity: velocityY * Self.orbitPerPoint,
      coasting: !reduceMotion)
  }

  func zoom(by scale: Float) {
    camera.zoom(by: scale)
    aimLens()
  }

  func endZoom() {
    camera.release(yawVelocity: 0, pitchVelocity: 0, coasting: !reduceMotion)
  }

  private func aimLens() {
    lens.look(at: NookiCamera.target, from: camera.position, relativeTo: nil)
  }

  // MARK: - Touch

  /// Handles a tap on `entity`, and returns the event to report, if any. A target reacts at once,
  /// and a second quick tap anywhere sends the camera home instead.
  func tap(_ entity: Entity, at time: TimeInterval) -> PetSceneEvent? {
    if renovation.isOn { return nil }
    if tapTimer.isDoubleTap(at: time) {
      camera.goHome(animated: !reduceMotion)
      aimLens()
      return nil
    }
    guard let target = NookiTarget(rawValue: entity.name) else { return nil }
    return perform(target)
  }

  /// Runs what a tap on `target` does. The accessibility actions come in here too.
  func perform(_ target: NookiTarget) -> PetSceneEvent? {
    let touch = NookiTouch.of(target, world: world, noteIsOpen: noteIsOpen)
    lookTowards(target)
    switch touch.reaction {
    case .wakeAndHop:
      petStart = clock
    case .toggleLamp:
      lampIsOn.toggle()
    case .toggleNote:
      noteIsOpen.toggle()
    case .wobble(let target):
      wobbles[target] = clock
    case .catchPlane:
      flight.tap(at: clock - stepStart)
    case .nudgeYarn:
      physics.setVelocity(NookiPhysics.flick(screenVelocity: [240, -240], cameraYaw: camera.yaw))
    }
    return touch.event
  }

  /// Turns Mochi's whole body towards a tapped object for a moment. No clip turns the head alone.
  private func lookTowards(_ target: NookiTarget) {
    guard !reduceMotion, target != .mochi, let holder = holders[target] ?? noteHolder(target) else {
      return
    }
    look(at: holder.position(relativeTo: nil))
  }

  private func look(at point: SIMD3<Float>) {
    let offset = point - mochi.position(relativeTo: nil)
    let facing = atan2(-offset.x, -offset.z)
    let turn = remainder(facing - NookiChoreography.restHeading, 2 * .pi)
    lookGoal = min(max(turn, -Self.lookLimit), Self.lookLimit)
    lookStart = clock
  }

  private func noteHolder(_ target: NookiTarget) -> Entity? {
    target == .note ? note : nil
  }

  // MARK: - Updates

  private func tick(_ delta: TimeInterval) {
    guard isOnScreen, isLoaded else { return }
    if settlingFrames > 0 {
      settlingFrames -= 1
      if settlingFrames == 0 {
        NookiTrace.mark("room on screen")
        onReady?()
      }
      return
    }
    clock += delta
    idleDelta += delta
    guard isBusy || idleDelta >= Self.idleStep else { return }
    let step = idleDelta
    idleDelta = 0
    stepTilt(Float(step))
    stepYarn(step)
    renovation.step(Float(step), reduceMotion: reduceMotion)
    if !camera.isAtRest {
      camera.step(Float(step))
      aimLens()
    }
    apply(elapsed: clock - stepStart, delta: Float(step))
  }

  /// True while something should move at full rate. A sleeping room runs at the idle step.
  private var isBusy: Bool {
    !camera.isAtRest || renovation.isMoving || tilt.isMoving || tilt.pull != .zero
      || yarnPlay.isPlaying
      || ballSpeed > NookiYarnPlay.noticeSpeed / 2 || world.activity != .sleeping || petStart != nil
      || !wobbles.isEmpty
      || lookStart != nil || lookTurn != 0
      || noteOpening != (noteIsOpen ? 1 : 0)
  }

  private func apply(elapsed: Double, delta: Float) {
    let isFlying = world.noteArrived && !reduceMotion
    let shownTime = isFlying ? flight.choreographyTime(elapsed) : elapsed
    var frame = NookiChoreography.frame(world, elapsed: shownTime, reduceMotion: reduceMotion)
    if isFlying {
      frame.hop = max(frame.hop, flight.leap(elapsed))
      if !flight.isCaught(at: elapsed) { frame.note = 0 }
    }
    applyPlane(isFlying: isFlying, elapsed: elapsed)
    if let petStart {
      let since = clock - petStart
      frame = frame.combined(with: NookiMotion.pet(since, reduceMotion: reduceMotion))
      if since >= NookiMotion.petLength { self.petStart = nil }
    }
    var awaySpot: SIMD3<Float>?
    if yarnPlay.isPlaying {
      let pose = yarnPlay.pose
      var body = pose.frame
      body.note = frame.note
      body.pinned = frame.pinned
      frame = body
      awaySpot = pose.spot
    }
    applyBody(frame, awaySpot: awaySpot, delta: delta)
    applyClip(frame)
    applyHolders()
    applyLamp(delta)
    applyBowl(delta)
    applyNote(frame, elapsed: elapsed, delta: delta)
  }

  private func applyBody(_ frame: NookiFrame, awaySpot: SIMD3<Float>?, delta: Float) {
    if let lookStart, clock - lookStart >= NookiMotion.lookLength { self.lookStart = nil }
    let goal = lookStart == nil ? 0 : lookGoal
    lookTurn = Self.eased(lookTurn, to: goal, rate: 7, delta: delta, snap: reduceMotion)

    if !NookiClip.walksWithRig {
      let upright = 0.1 * frame.stretch
      let wide = -0.05 * frame.stretch
      mochi.scale = [1 + wide, 1 + upright, 1 + wide]
    }

    var spot = mix(Self.bedSpot, Self.wallSpot, t: frame.walk)
    let drop = min(frame.walk / Self.bedDrop, 1)
    spot.y = Self.bedSpot.y + (Self.wallSpot.y - Self.bedSpot.y) * drop
    if let awaySpot { spot = awaySpot }
    mochi.position = spot + [0, 0.02 * frame.wake + 0.05 * frame.hop + 0.07 * frame.stepHeight, 0]
    mochi.orientation = simd_quatf(angle: frame.heading + lookTurn, axis: [0, 1, 0])
  }

  private func applyClip(_ frame: NookiFrame) {
    let clip = NookiClip.choose(frame: frame, yarn: yarnPlay.phase)
    let travel = yarnPlay.isPlaying ? yarnPlay.travelSpeed : Self.walkPace
    animator?.play(clip, rate: clip == .walk ? NookiClip.walkRate(forTravelAt: travel) : 1)
  }

  private func applyHolders() {
    for (target, start) in wobbles where clock - start >= NookiMotion.wobbleLength {
      wobbles[target] = nil
    }
    for (target, holder) in holders {
      guard let base = holderOrientations[target] else { continue }
      var tilt =
        wobbles[target].map {
          NookiMotion.wobble(clock - $0, reduceMotion: reduceMotion)
        } ?? 0
      if target == .plant { tilt += NookiMotion.sway(clock, reduceMotion: reduceMotion) }
      if tilt != 0 || wobbles[target] != nil || target == .plant {
        holder.orientation = base * simd_quatf(angle: tilt, axis: [0, 0, 1])
      }
    }
  }

  private func applyLamp(_ delta: Float) {
    let flicker = NookiMotion.flicker(clock, reduceMotion: reduceMotion)
    let goal: Float = lampIsOn ? 1 : 0
    lampLight.components[PointLightComponent.self]?.intensity =
      Self.lampIntensity * lampLevel * flicker
    let lanternFlicker = NookiMotion.flicker(clock + 1.7, reduceMotion: reduceMotion)
    lanternLight.components[PointLightComponent.self]?.intensity =
      Self.lanternIntensity * lanternFlicker
    guard lampLevel != goal else { return }
    lampLevel = Self.eased(lampLevel, to: goal, rate: 6, delta: delta, snap: reduceMotion)
    for part in lampParts {
      guard var material = part.model.model?.materials[part.material] as? PhysicallyBasedMaterial
      else { continue }
      material.emissiveIntensity = part.glow * (0.05 + 0.95 * lampLevel)
      part.model.model?.materials[part.material] = material
    }
  }

  private func applyBowl(_ delta: Float) {
    let goal = play.treat.bowlFill
    guard bowlLevel != goal else { return }
    bowlLevel = Self.eased(bowlLevel, to: goal, rate: 3, delta: delta, snap: reduceMotion)
    bowlFill.isEnabled = bowlLevel > 0
    bowlFill.scale = [0.5 + 0.5 * bowlLevel, max(bowlLevel, 0.01), 0.5 + 0.5 * bowlLevel]
  }

  private func applyPlane(isFlying: Bool, elapsed: Double) {
    let inFlight = isFlying && !flight.isCaught(at: elapsed)
    plane.entity.isEnabled = inFlight
    guard inFlight else { return }
    let pose = flight.pose(
      at: elapsed, mochi: mochi.position + [0, Self.carryHeight, 0])
    plane.show(pose)
    look(at: pose.position)
    lookStart = clock
  }

  private func applyNote(_ frame: NookiFrame, elapsed: Double, delta: Float) {
    noteOpening = Self.eased(
      noteOpening, to: noteIsOpen ? 1 : 0, rate: 8, delta: delta, snap: reduceMotion)
    note.isEnabled = frame.note > 0
    let carried = mochi.position + [0, Self.carryHeight, 0]
    let hanging = mix(mix(Self.noteStart, carried, t: frame.note), Self.noteHome, t: frame.pinned)
    let toLens = simd_normalize(NookiCamera.target - camera.position)
    let reading = camera.position + toLens * Self.noteReadingDistance
    note.position = mix(hanging, reading, t: noteOpening)
    let hangingScale = 0.3 + 0.25 * frame.note + 0.45 * frame.pinned
    note.scale = .one * (hangingScale + (Self.noteReadingScale - hangingScale) * noteOpening)
    let swing = reduceMotion ? 0 : 0.2 * sin(Float(elapsed) * 3) * (1 - frame.pinned)
    note.orientation = simd_slerp(
      simd_quatf(angle: swing, axis: [0, 0, 1]), lens.orientation(relativeTo: nil), noteOpening)
  }

  private static func eased(
    _ value: Float, to goal: Float, rate: Float, delta: Float, snap: Bool
  ) -> Float {
    let next = value + (goal - value) * (1 - exp(-rate * delta))
    return snap || abs(goal - next) < 0.005 ? goal : next
  }

  // MARK: - Room

  /// The room's simple shapes, baked into the room's file. Sizes match the bake.
  static let shellParts: [(name: String, size: SIMD3<Float>, position: SIMD3<Float>)] = [
    ("shell_floor", [1.3, 0.08, 1.3], [0.05, -0.04, 0.05]),
    ("shell_wall_left", [0.06, 0.86, 1.3], [-0.63, 0.43, 0.05]),
    ("shell_wall_back", [1.36, 0.86, 0.06], [0.02, 0.43, -0.63]),
    ("shell_skirting_left", [0.012, 0.09, 1.2], [-0.594, 0.045, 0.05]),
    ("shell_skirting_back", [1.2, 0.09, 0.012], [0.05, 0.045, -0.594]),
    ("shell_wire", [0.76, 0.006, 0.006], [-0.08, 0.6, -0.59]),
  ]
  private static let shellTones: [Tone] = [.honey, .plaster, .plaster, .walnut, .walnut, .ink]

  /// The named baked shape in , or a plain generated one if the bake is missing it.
  private func shape(
    _ name: String, _ tone: Tone, otherwise generated: @autoclosure () -> MeshResource
  ) async -> ModelEntity {
    var mesh: MeshResource?
    if let baked = try? await loadShape(name) {
      Self.visit(baked) { entity in
        if mesh == nil { mesh = entity.components[ModelComponent.self]?.mesh }
      }
    }
    return ModelEntity(mesh: mesh ?? generated(), materials: [Self.clay(tone)])
  }

  private func buildRoom() async {
    var built: [ModelEntity] = []
    for (part, tone) in zip(Self.shellParts, Self.shellTones) {
      let model = await shape(part.name, tone, otherwise: .generateBox(size: part.size))
      model.position = part.position
      room.addChild(model)
      built.append(model)
    }
    for surface in built.prefix(3) {
      Self.makeTappable(
        surface, size: surface.visualBounds(relativeTo: surface).extents, center: .zero)
    }
    renovation.setSurfaces(
      walls: [built[1], built[2]], floor: built[0], wall: Tone.plaster.rgbVector,
      ground: Tone.honey.rgbVector)
    renovation.addFixed(centre: [Self.bedSpot.x, Self.bedSpot.z], half: [0.28, 0.28])
    renovation.addFixed(centre: [Self.bowlPosition.x, Self.bowlPosition.z], half: [0.1, 0.1])
    streakMarks.position = [0.2, 0.72, -0.597]
    room.addChild(streakMarks)
  }

  private func buildBowl() async {
    let bowl = Entity()
    bowl.position = Self.bowlPosition
    let dish = await shape(
      "shape_dish", .heart, otherwise: .generateCylinder(height: 0.04, radius: 0.075))
    dish.position = [0, 0.02, 0]
    bowl.addChild(dish)
    let treats = await shape("shape_treats", .walnut, otherwise: .generateSphere(radius: 0.066))
    treats.scale = [1, 0.5, 1]
    bowlFill.addChild(treats)
    bowlFill.position = [0, 0.04, 0]
    bowlFill.isEnabled = false
    bowl.addChild(bowlFill)
    room.addChild(bowl)
  }

  /// One mark per day of the streak, in rows of seven like a calendar scratched on the wall.
  private func buildStreakMarks(_ streak: Int) {
    for mark in Array(streakMarks.children) { mark.removeFromParent() }
    for day in 0..<min(streak, 28) {
      let mark = ModelEntity(
        mesh: .generateBox(width: 0.008, height: 0.03, depth: 0.004),
        materials: [Self.clay(.paper)])
      mark.position = [Float(day % 7) * 0.02, -Float(day / 7) * 0.04, 0]
      streakMarks.addChild(mark)
    }
  }

  private func buildNote() async {
    note.name = NookiTarget.note.rawValue
    let sheet = ModelEntity(
      mesh: .generateBox(width: 0.22, height: 0.28, depth: 0.004),
      materials: [Self.clay(.paper)])
    note.addChild(sheet)
    noteSheet = sheet
    room.addChild(plane.entity)
    let mark = await shape("shape_note_mark", .heart, otherwise: .generateSphere(radius: 0.022))
    mark.position = [0, -0.02, 0.003]
    mark.scale = [1, 1, 0.1]
    note.addChild(mark)
    noteMark = mark
    let peg = ModelEntity(
      mesh: .generateBox(width: 0.018, height: 0.05, depth: 0.012),
      materials: [Self.clay(.walnut)])
    peg.position = [0, 0.14, 0.006]
    note.addChild(peg)
    note.isEnabled = false
    Self.makeTappable(note, size: [0.26, 0.32, 0.02], center: .zero)
    room.addChild(note)
    if let shownPaper { applyPaper(shownPaper.material, hasDrawing: shownPaper.hasDrawing) }
  }

  /// A large collider behind everything, so a tap that misses every object still arrives and can
  /// count towards a double tap.
  private func buildBackstop() {
    let backstop = Entity()
    backstop.position = [0, 0, -30]
    Self.makeTappable(backstop, size: [80, 80, 0.1], center: .zero)
    lens.addChild(backstop)
  }

  private func place(_ item: NookiFurniture) async {
    let (width, height, position, yaw, target) = (
      item.width, item.height, item.position, item.yaw, item.target
    )
    do {
      let model = try await loadModel(item.name)
      let bounds = model.visualBounds(relativeTo: nil)
      let scale =
        width.map { $0 / max(bounds.extents.x, bounds.extents.z) }
        ?? height.map { $0 / bounds.extents.y } ?? 1
      model.scale = .one * scale
      model.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
      let size = bounds.extents * scale
      if target == .yarn {
        model.position.y -= size.y / 2
        physics.ball.name = NookiTarget.yarn.rawValue
        physics.ball.addChild(model)
        room.addChild(physics.ball)
        physics.prepareBall(at: position)
        holders[.yarn] = physics.ball
        return
      }
      let holder = Entity()
      holder.position = position
      holder.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
      holder.addChild(model)
      room.addChild(holder)
      if item.name == NookiFurniture.lanternName { lantern = holder }
      if item.isSolid {
        physics.addSolid(to: holder, size: size)
        renovation.register(item.name, holder: holder, half: item.footprint(size))
        Self.makeTappable(holder, size: size, center: [0, size.y / 2, 0])
      }
      if let target {
        holder.name = target.rawValue
        holders[target] = holder
        holderOrientations[target] = holder.orientation
        Self.makeTappable(holder, size: size, center: [0, size.y / 2, 0])
      }
    } catch {
      Self.log.error("\(String(describing: error), privacy: .public)")
    }
  }

  private static func makeTappable(
    _ entity: Entity, size: SIMD3<Float>, center: SIMD3<Float>
  ) {
    entity.components.set(
      CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: center)]))
    entity.components.set(InputTargetComponent())
  }

  private func findLampParts() {
    guard let lamp = holders[.lamp] else { return }
    Self.visit(lamp) { entity in
      guard let model = entity as? ModelEntity, let materials = model.model?.materials else {
        return
      }
      for (index, material) in materials.enumerated() {
        if let glowing = material as? PhysicallyBasedMaterial, glowing.emissiveIntensity > 0 {
          lampParts.append((model, index, glowing.emissiveIntensity))
        }
      }
    }
  }

  // MARK: - Mochi

  /// Starts Mochi ahead of the furniture, on its own task so that a slow cat cannot hold up the
  /// room. Mochi is reported missing on failure, or at the deadline if the load is still going;
  /// a late arrival clears that.
  private func startLoadingMochi() {
    mochiLoading = Task { await loadMochi() }
    let deadline = mochiDeadline
    Task { [weak self] in
      try? await Task.sleep(for: deadline)
      self?.reportMochiIfAbsent()
    }
  }

  private func loadMochi() async {
    do {
      let model = try await loadModel(NookiAssets.mochiName)
      guard let offset = Self.mochiOffset(model.visualBounds(relativeTo: nil)) else {
        throw NookiLoadError.noGeometry("Cat")
      }
      model.scale = .one * Self.mochiScale
      model.position = offset
      animator = NookiCatAnimator(model: model)
      animator?.play(.sleep, blend: 0)
      mochi.addChild(model)
      hasMochi = true
      NookiTrace.mark("Mochi placed")
      setMochiMissing(false)
    } catch {
      Self.log.error("\(String(describing: error), privacy: .public)")
      setMochiMissing(true)
    }
  }

  private func reportMochiIfAbsent() {
    if !hasMochi { setMochiMissing(true) }
  }

  /// Where the model goes so that it sits centred on its own floor, or nil for bounds that hold
  /// nothing a viewer could see.
  static func mochiOffset(_ bounds: BoundingBox) -> SIMD3<Float>? {
    let corners = [bounds.min, bounds.max]
    guard !bounds.isEmpty, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    else { return nil }
    return -[bounds.center.x, bounds.min.y, bounds.center.z] * mochiScale
  }

  /// A crossed-out card on the bed, so a cat that failed to load cannot pass for an empty room.
  private func setMochiMissing(_ missing: Bool) {
    guard missing != isMochiMissing else { return }
    isMochiMissing = missing
    missingMark.removeFromParent()
    if missing {
      if missingMark.children.isEmpty { buildMissingMark() }
      mochi.addChild(missingMark)
    }
    onMochiMissing?(missing)
  }

  private func buildMissingMark() {
    missingMark.name = Self.missingMarkName
    missingMark.position = [0, 0.14, 0]
    let card = ModelEntity(
      mesh: .generateBox(width: 0.2, height: 0.2, depth: 0.008), materials: [Self.clay(.paper)])
    missingMark.addChild(card)
    for angle in [Float.pi / 4, -Float.pi / 4] {
      let bar = ModelEntity(
        mesh: .generateBox(width: 0.2, height: 0.024, depth: 0.012),
        materials: [Self.clay(.heart)])
      bar.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
      missingMark.addChild(bar)
    }
  }

  // MARK: - Light

  private static func ambientEnvironment() async -> EnvironmentResource? {
    guard let image = ambientGradient() else { return nil }
    return try? await EnvironmentResource(equirectangular: image)
  }

  private func addLighting(environment: EnvironmentResource?) {
    if let environment {
      let ambient = Entity()
      ambient.components.set(
        ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.6))
      room.addChild(ambient)
      let receiver = ImageBasedLightReceiverComponent(imageBasedLight: ambient)
      Self.visit(room) { $0.components.set(receiver) }
    }

    let sun = Entity()
    sun.components.set(
      DirectionalLightComponent(color: Tone.evening.color, intensity: 1100))
    sun.components.set(DirectionalLightComponent.Shadow(maximumDistance: 4, depthBias: 2))
    sun.look(at: .zero, from: [1.8, 1.5, 0.7], relativeTo: nil)
    room.addChild(sun)

    lanternLight.position = [0.54, 0.34, 0.42]
    lanternLight.components.set(
      PointLightComponent(
        color: Tone.evening.color, intensity: Self.lanternIntensity, attenuationRadius: 0.8))
    room.addChild(lanternLight)

    lampLight.position = [0.56, 0.52, 0.06]
    lampLight.components.set(
      PointLightComponent(
        color: Tone.lamp.color, intensity: Self.lampIntensity, attenuationRadius: 1.4))
    room.addChild(lampLight)
  }

  /// Slow specks in the lamplight. Few and short-lived, to keep the particle cost low.
  private func buildDust() {
    var emitter = ParticleEmitterComponent()
    emitter.emitterShape = .box
    emitter.emitterShapeSize = [0.9, 0.5, 0.9]
    emitter.birthLocation = .volume
    emitter.speed = 0.006
    emitter.mainEmitter.birthRate = 5
    emitter.mainEmitter.lifeSpan = 6
    emitter.mainEmitter.size = 0.005
    emitter.mainEmitter.color = .constant(.single(Tone.lamp.color))
    emitter.mainEmitter.blendMode = .additive
    emitter.mainEmitter.opacityCurve = .gradualFadeInOut
    emitter.mainEmitter.isLightingEnabled = false
    dust.position = [0.2, 0.42, 0.1]
    dust.components.set(emitter)
    dust.isEnabled = !reduceMotion
    room.addChild(dust)
  }

  private static func visit(_ entity: Entity, _ body: (Entity) -> Void) {
    body(entity)
    for child in entity.children { visit(child, body) }
  }

  /// A warm vertical gradient for ambient light: bright above, like a ceiling in lamplight.
  private static func ambientGradient() -> CGImage? {
    let colors = [Tone.ceiling.cgColor, Tone.bounce.cgColor] as CFArray
    guard
      let context = CGContext(
        data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
    else { return nil }
    context.drawLinearGradient(
      gradient, start: CGPoint(x: 0, y: 32), end: .zero, options: [])
    return context.makeImage()
  }

  private static func clay(_ tone: Tone) -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    material.baseColor = .init(tint: tone.color)
    material.roughness = 0.85
    material.metallic = 0.0
    return material
  }
}

private enum Tone {
  case honey, plaster, walnut, ink, paper, heart, lamp, evening, ceiling, bounce

  var rgbVector: SIMD3<Float> {
    SIMD3(Float(rgb.0), Float(rgb.1), Float(rgb.2))
  }

  private var rgb: (CGFloat, CGFloat, CGFloat) {
    switch self {
    case .honey: (0.72, 0.5, 0.3)
    case .plaster: (0.76, 0.56, 0.44)
    case .walnut: (0.36, 0.23, 0.16)
    case .ink: (0.1, 0.08, 0.08)
    case .paper: (0.98, 0.96, 0.9)
    case .heart: (0.85, 0.27, 0.27)
    case .lamp: (1, 0.82, 0.6)
    case .evening: (1, 0.66, 0.42)
    case .ceiling: (1, 0.84, 0.66)
    case .bounce: (0.5, 0.34, 0.28)
    }
  }

  var color: RealityKit.Material.Color {
    RealityKit.Material.Color(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
  }
  var cgColor: CGColor { CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) }
}

typealias NookiModelLoader = @MainActor @Sendable (String) async throws(NookiLoadError) -> Entity

enum NookiLoadError: Error, Equatable {
  case unreadable(String, reason: String)
  case noGeometry(String)
}

/// One bought piece of the room and where it stands. Fits by `width` or `height`.
struct NookiFurniture: Sendable {
  var name: String
  var width: Float?
  var height: Float?
  var position: SIMD3<Float>
  var yaw: Float
  var target: NookiTarget?
  /// True for a piece the ball bounces off and that can be moved.
  var isSolid = false

  static let lanternName = "Item_lantern"
  static let tableName = "Item_teatable"
  static let lampName = "Item_lamp"
  private static let standingShare: Float = 0.8

  /// Half the floor this piece takes up, for a model of `size`.
  func footprint(_ size: SIMD3<Float>) -> SIMD2<Float> {
    let (across, along) = (abs(cos(yaw)), abs(sin(yaw)))
    return SIMD2(
      across * size.x + along * size.z, along * size.x + across * size.z) / 2 * Self.standingShare
  }

  @MainActor static let items = [
    NookiFurniture(name: "Item_rug", width: 0.86, position: [0.05, 0.002, 0.12], yaw: 0),
    NookiFurniture(
      name: "Item_donutbed", width: 0.5, position: [0.05, 0.012, 0.12], yaw: 0, target: .bed),
    NookiFurniture(
      name: "Item_bookcase", height: 0.72, position: [-0.46, 0, -0.1], yaw: .pi / 2,
      target: .bookcase, isSolid: true),
    NookiFurniture(
      name: "Item_monstera", height: 0.62, position: [-0.4, 0, -0.42], yaw: 0, target: .plant,
      isSolid: true),
    NookiFurniture(
      name: "Item_armchair", width: 0.5, position: [0.42, 0, -0.38], yaw: -.pi / 4, isSolid: true),
    NookiFurniture(
      name: "Item_lamp", height: 0.46, position: [0.62, 0, 0.02], yaw: 0, target: .lamp,
      isSolid: true),
    NookiFurniture(
      name: "Item_teatable", height: 0.2, position: [0.54, 0, 0.42], yaw: 0, isSolid: true),
    NookiFurniture(name: "Item_lantern", height: 0.15, position: [0.54, 0.2, 0.42], yaw: 0),
    NookiFurniture(
      name: "Item_tower", height: 0.62, position: [-0.46, 0, 0.5], yaw: 0, isSolid: true),
    NookiFurniture(name: "Item_print", height: 0.26, position: [0.45, 0.46, -0.59], yaw: 0),
    NookiFurniture(
      name: "Item_yarn", width: 0.14, position: NookiDiorama.yarnPosition, yaw: 0, target: .yarn),
    NookiFurniture(name: "Item_mouse", height: 0.07, position: [-0.2, 0, 0.56], yaw: 0.8),
  ]
}
