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
final class NookiDiorama: CatPlayStage {
  let root = Entity()
  /// Whether a measuring run has been told this room is drawing since it last came on screen.
  private var isAnnounced = false
  /// Called when the room has rendered in a view and a poster over it can go.
  var onReady: (() -> Void)?
  /// Called when the cat is found to be missing, and again if a late load puts things right.
  var onCatMissing: ((Bool) -> Void)?
  /// Called when an opening asked for through ``flyIn(_:)`` starts, once the diorama is built.
  var onOpeningStarted: (() -> Void)?
  /// Called when an opening asked for through ``flyIn(_:)`` is over.
  var onOpeningEnded: (() -> Void)?

  let room = Entity()
  let lens = PerspectiveCamera()
  let catHolder = Entity()
  private let note = Entity()
  private let bowlFill = Entity()
  private let streakMarks = Entity()
  private let lampLight = Entity()
  private let lanternLight = Entity()
  private let sunLight = Entity()
  private var ambientLight: Entity?
  private let dust = Entity()
  private var holders: [NookiTarget: Entity] = [:]
  private var holderOrientations: [NookiTarget: simd_quatf] = [:]
  private var wobbles: [NookiTarget: Double] = [:]
  private var lampParts: [(model: ModelEntity, material: Int, glow: Float)] = []
  var world = PetWorld()
  private var play = PetPlayState()
  private(set) var clock = 0.0
  private var stepStart = 0.0
  var petStart: Double?
  private var lookStart: Double?
  private var lookGoal: Float = 0
  private var lookTurn: Float = 0
  private var idleDelta = 0.0
  private(set) var isOnScreen = false
  private var viewsShowing = Set<UUID>()
  private(set) var hasRehearsed = false
  private var isLoaded = false
  private(set) var loading: Task<Void, Never>?
  private(set) var catLoading: Task<Void, Never>?
  private(set) var isCatMissing = false
  var hasCat = false
  /// The cat's clips, look and coat, once loaded.
  private(set) var rig: CatRig?
  var behaviour = CatBehaviour(clips: [:])
  /// The hands on the cat: petting, play and their cooldowns.
  let hands = CatHands()
  /// The toys Nooki adds to its floor, and the game going on with one.
  let toys = RoomToys()
  let laserDot = CatToyModels.laserDot(length: NookiDiorama.catReach)
  /// Where the room reports what happens outside a touch, such as a game the cat won.
  var report: (@MainActor (PetSceneEvent) -> Void)?
  /// The cat's length in the room, measured once it is placed.
  private var catLength: Float?
  /// What the cat's brain shows now: whether it is awake and in the mood to bat, and the Play
  /// step that asks for a chase.
  private var brain: CatBrainFrame?
  /// A chase the brain asked for, waiting for the cat to be free.
  private var chaseWanted = false
  /// The finger on the room and the view it is in, for a cat that bats at one resting near the
  /// edge.
  private var fingerRest = CatFingerRest()
  private var fingerView = SIMD2<Float>.zero
  /// The purr and its hearts, for the view to draw.
  let purr = CatPurr()
  /// A trip away from the bed and back, while one is playing.
  var trip: CatTrip?
  var tripPose: CatTrip.Pose?
  private var lastBat = -Double.infinity
  private var rollingUntil = -Double.infinity
  /// Where the finger last stroked the cat, in the view's points, for the hearts.
  var strokePoint: CGPoint?
  private var greetPending = false
  private var lastSeenSaved = -Double.infinity
  /// The cat asked for, and the one on show (the standard cat stands in for one that will not load).
  private(set) var catChoice = CatChoice.standard
  private(set) var shownCat: CatChoice?
  private var catModel: Entity?
  /// Where the cat looks: a point the finger is over, until a moment after it lifts.
  private var gazePoint: SIMD3<Float>?
  private var gazeUntil = 0.0
  private let missingMark = Entity()
  private let loadModel: NookiModelLoader
  private let loadShape: NookiModelLoader
  /// Loads the cat for a choice, with the choice it really shows.
  private let loadCatFor: (CatChoice) async throws(NookiLoadError) -> (Entity, CatChoice)
  private let tiltSource: any NookiTiltSource
  private var tilt = NookiTilt()
  private var ambientReceiver: ImageBasedLightReceiverComponent?
  private var onAmbient: ((ImageBasedLightReceiverComponent) -> Void)?
  let physics = NookiPhysics()
  private var flight = NookiPlaneFlight()
  private lazy var plane = NookiPaperPlane(paper: Self.clay(.paper))
  private var noteSheet: ModelEntity?
  private var noteMark: ModelEntity?
  let renovation: NookiRenovation
  var yarnPlay = NookiYarnPlay(
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
  private let catDeadline: Duration
  private var settlingFrames = NookiDiorama.framesBeforeReady
  private let frames = FrameClock()
  private var isRehearsing = false
  var camera = NookiCamera()
  var tapTimer = NookiTapTimer()
  var reduceMotion = false
  private var lampIsOn = true
  private var lampLevel: Float = 1
  var noteIsOpen = false
  private var noteOpening: Float = 0
  private var bowlLevel: Float = 0
  private let windowLight = Entity()
  private var windowPane: ModelEntity?
  /// Eased 0...1 towards the frame's light.
  private var light: Float = 0
  /// The opening the host asked for, waiting for the room to be on screen.
  private var pendingFlyIn: PetSceneFlyIn?
  var opening: SceneFlight?
  /// How far the room's lights are up, from dark at 0 to full at 1. Only an opening lowers it.
  private var lightsLevel: Float = 1
  private var shownLightsLevel: Float = 1
  /// How far the note has grown in, from hidden at 0. Only an opening lowers it.
  private var noteReveal: Float = 1
  private var dayLight: PetSceneDayLight?
  var fillsView = false {
    didSet { if fillsView != oldValue { fit(to: fittedSize) } }
  }
  var fittedSize = SIMD2<Float>(393, 852)

  nonisolated static let catScale: Float = 1.25
  static let missingMarkName = "cat-missing"
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "NookiDiorama")

  private static let orbitPerPoint: Float = 0.006
  private static let idleStep = 1.0 / 30
  private static let framesBeforeReady = 4
  private static let rehearsalFrames = 8
  private static let lampIntensity: Float = 2600
  private static let lanternIntensity: Float = 500
  private static let sunIntensity: Float = 1100
  private static let ambientExponent: Float = 0.6
  /// How much darker than usual the ambient light is with the room's lights all the way down.
  private static let darkAmbientShift: Float = -3

  // The cat lies in the bed in the middle of the rug, and hops to a spot under the wire.
  static let bedSpot: SIMD3<Float> = [0.05, 0.095, 0.12]
  static let wallSpot: SIMD3<Float> = [0.08, 0.012, -0.38]
  /// Share of the walk spent dropping from the bed to the floor.
  private static let bedDrop: Float = 0.25
  private static let carryHeight: Float = 0.34
  /// How fast the reach plays while taping, so it fits the time at the wall.
  private static let tapingRate: Float = 1.4
  private static let noteHome: SIMD3<Float> = [0.08, 0.46, -0.565]
  private static let noteStart: SIMD3<Float> = [0.75, 1.05, -0.1]
  /// How far in front of the lens an opened note sits, and how much larger it gets.
  static let noteReadingDistance: Float = 2.4
  private static let noteReadingScale: Float = 2
  /// The lens's clip planes, in metres. The camera stands some nine metres from the room and an
  /// opened note comes to `noteReadingDistance` in front of it, so a near plane this far out
  /// keeps the depth fine enough for the paint, marks and window pane laid millimetres proud of
  /// the walls. The default near plane of a centimetre let them shimmer as the room turned.
  static let nearClip: Float = 0.2
  static let farClip: Float = 60
  static let yarnPosition: SIMD3<Float> = [0.36, 0, 0.54]
  private static let lookLimit: Float = 1
  /// How fast the cat covers its walk to the wall, in metres a second.
  static let walkPace: Float = 0.23
  static let fieldOfView: Float = 30
  private static let noticeDistance: Float = 0.6
  static let bowlPosition: SIMD3<Float> = [0.12, 0, 0.6]
  /// Extra turn towards the window when the partner is here.
  private static let windowTurn: Float = -0.55
  private static let windowCentre: SIMD3<Float> = [-0.28, 0.52, -0.59]
  private static let lightPerSecond: Float = 1.5

  /// Starts empty and cheap, so a view can hold one before anything heavy has run.
  init(
    loadModel: NookiModelLoader? = nil,
    loadShape: NookiModelLoader? = nil,
    catDeadline: Duration = .seconds(12),
    tiltSource: any NookiTiltSource = NookiTiltSources.standard(),
    layoutStore: NookiLayoutStore = NookiLayoutStore(defaults: .standard)
  ) {
    renovation = NookiRenovation(store: layoutStore)
    let assets = NookiAssets()
    let bundled: NookiModelLoader = { name throws(NookiLoadError) in try await assets.model(name) }
    self.loadModel = loadModel ?? bundled
    self.loadShape = loadShape ?? bundled
    if let loadModel {
      loadCatFor = { choice throws(NookiLoadError) in (try await loadModel("Cat"), choice) }
    } else {
      loadCatFor = { choice throws(NookiLoadError) in
        guard let loaded = await Self.loadCatModel(choice) else {
          throw .unreadable(CatCatalog.resourceName(choice.model), reason: "no cat")
        }
        return loaded
      }
    }
    self.tiltSource = tiltSource
    self.catDeadline = catDeadline
    root.addChild(room)
    room.isEnabled = false
    lens.camera.fieldOfViewInDegrees = Self.fieldOfView
    lens.camera.near = Self.nearClip
    lens.camera.far = Self.farClip
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
    startLoadingCat()
    let furniture = NookiFurniture.items.map { item in Task { await place(item) } }
    let environment = Task { await Self.ambientEnvironment() }
    await buildRoom()
    physics.buildShell(in: room)
    await buildBowl()
    await Task.yield()
    await buildNote()
    buildBackstop()
    buildToys()
    buildTreat()
    catHolder.position = Self.bedSpot
    catHolder.name = NookiTarget.cat.rawValue
    Self.makeTappable(catHolder, size: [0.34, 0.26, 0.34], center: [0, 0.13, 0])
    room.addChild(catHolder)
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
  func startRehearsal(done: @escaping () -> Void) {
    NookiTrace.mark("room rehearsing")
    room.isEnabled = true
    var count = Self.rehearsalFrames
    isRehearsing = true
    frames.isPaused = false
    frames.run { [weak self] _ in
      count -= 1
      guard count == 0, let self else { return }
      self.frames.stop()
      self.isRehearsing = false
      self.room.isEnabled = self.isOnScreen
      self.hasRehearsed = true
      NookiTrace.mark("room rehearsed")
      done()
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
    let sameStep = world.step == self.world.step
    self.world = world
    guard !sameStep else { return }
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
    behaviour.follow(play.life ?? LifeDrive())
    if petted {
      petStart = clock
      behaviour.react(.pet, at: clock)
      if let response = hands.play.handle(.partnerPetted, at: clock) { _ = show(response) }
    }
    if isLoaded, play.streak != streakMarks.children.count { buildStreakMarks(play.streak) }
  }

  /// A new entity holding the room, for one view to add to its content. A view that goes removes
  /// what it added, so with a holder each it takes only its own, never the room another view
  /// has taken since.
  func makeHolder() -> Entity {
    let holder = Entity()
    holder.addChild(root)
    return holder
  }

  /// Starts stepping the room for a view that has just added it. A diorama outlives its view, so
  /// each new view starts the steps again, with its own settling before `onReady`.
  func startUpdates() {
    hasRehearsed = true
    isRehearsing = false
    settlingFrames = Self.framesBeforeReady
    frames.isPaused = !isOnScreen
    frames.run { [weak self] delta in
      NookiTrace.frame { self?.tick(delta) }
    }
  }

  func setReduceMotion(_ reduced: Bool) {
    reduceMotion = reduced
    dust.isEnabled = !reduced
    updateTiltFollowing()
  }

  /// Off screen, the room leaves the render and updates stop.
  /// Records whether `view` shows the room. A view replacing another appears before the old one
  /// goes, so the room stays on while any view shows it.
  func setOnScreen(_ onScreen: Bool, in view: UUID) {
    if onScreen {
      viewsShowing.insert(view)
    } else {
      viewsShowing.remove(view)
    }
    let wasOnScreen = isOnScreen
    if !isOnScreen, !viewsShowing.isEmpty { NookiTrace.mark("room shown") }
    isOnScreen = !viewsShowing.isEmpty
    room.isEnabled = isOnScreen && isLoaded
    if !isRehearsing { frames.isPaused = !isOnScreen }
    updateTiltFollowing()
    if isOnScreen, !wasOnScreen {
      greetPending = CatGreeting.isDue(lastSeen: CatSeen.last, now: .now)
    }
    if !isOnScreen, wasOnScreen { CatSeen.mark() }
    if !isOnScreen { isAnnounced = false }
  }

  // MARK: - Moments

  /// Follows the cat's brain. Play choosing a chase sends the yarn rolling once the cat is free;
  /// any other step lets a chase that never started go.
  func followBrain(_ frame: CatBrainFrame?) {
    guard frame != brain else { return }
    let before = brain
    brain = frame
    hands.play.learned = frame?.tricks ?? []
    let step = frame?.stack.step
    let isNew = step != before?.stack.step || frame?.stepStart != before?.stepStart
    if isNew { chaseWanted = step == .chase || step == .zoomies }
  }

  /// The finger turning the room is at `point`. Moving, it only turns the room; held still near
  /// the edge, it may get batted at.
  func fingerAt(_ point: SIMD2<Float>, in size: SIMD2<Float>) {
    fingerView = size
    fingerRest.moved(toX: Double(point.x), y: Double(point.y), at: clock)
  }

  func fingerLifted() {
    fingerRest.lifted()
  }

  /// A finger resting near the edge of the view catches the eye of a cat in the mood to play: it
  /// looks, then bats at it. A finger on the move, turning the room, is never batted at.
  private func batAtRestingFinger() {
    guard let rest = fingerRest.resting(at: clock), brain?.eager ?? false, trip == nil,
      !yarnPlay.isPlaying, world.activity == .sleeping, clock - lastBat > Self.batGap,
      CatEdge.isNearEdge(x: rest.x, width: Double(fingerView.x))
    else { return }
    let starts = clock - lastBat > Self.gameGap
    lastBat = clock
    fingerRest.restart(at: clock)
    followFinger(at: SIMD2(Float(rest.x), Float(rest.y)), in: fingerView)
    behaviour.react(.bat, at: clock)
    if starts { report?(.played) }
  }

  /// Bats closer together than this are one game.
  private static var gameGap: Double { 60 }

  /// Starts what the moments do when the brain wants them: a greeting after hours away for a cat
  /// that is awake, a chase when Play chose one, a bat at a resting finger.
  private func stepMoments() {
    purr.tick(at: clock, cat: strokePoint)
    if clock - lastSeenSaved > 30 {
      lastSeenSaved = clock
      CatSeen.mark()
    }
    let isFree =
      trip == nil && !yarnPlay.isPlaying && world.activity == .sleeping && !noteIsOpen
      && !reduceMotion && hasCat && opening == nil
    // A sleeping cat does not run up to the glass; the greeting is let go.
    if greetPending, brain?.stack.vitality == .asleep { greetPending = false }
    if greetPending, isFree {
      greetPending = false
      chaseWanted = false
      startGreeting()
    } else if chaseWanted, isFree {
      chaseWanted = false
      chaseYarn()
    }
    batAtRestingFinger()
  }

  /// Runs up from the bed towards the camera, headbutts it, and goes back.
  private func startGreeting() {
    let home = SIMD2(Self.bedSpot.x, Self.bedSpot.z)
    let eye = SIMD2(camera.position.x, camera.position.z)
    let near = CatTrip.towards(eye, from: home, upTo: Self.greetReach)
    let rest = NookiChoreography.restHeading
    let front = home + SIMD2(-sin(rest), -cos(rest)) * 0.3
    trip = CatTrip(
      from: home, heading: rest,
      legs: [
        .hold(behaviour.playable(.perk), seconds: 0.7, facing: eye),
        .walk(to: near, speed: Self.runSpeed),
        .hold(behaviour.playable(.headbutt), seconds: 1.8, facing: eye),
        .hold(behaviour.playable(.happy), seconds: 1.4, facing: eye),
        .walk(to: home, speed: Self.walkPace),
        .hold(behaviour.playable(.sit), seconds: 0.6, facing: front),
      ], at: clock)
    headLook(at: camera.position, for: 5)
  }

  /// Sends the yarn rolling, as if the cat had knocked it: the yarn game takes it from there.
  private func chaseYarn() {
    let angle = Float.random(in: 0..<(2 * .pi))
    let speed = Float.random(in: 650...900)
    flickYarn(velocityX: cos(angle) * speed, velocityY: sin(angle) * speed)
  }

  /// A trip's spot on the floor, as a place in the room: in the bed near it, on the floor beyond.
  func tripSpot(_ spot: SIMD2<Float>) -> SIMD3<Float> {
    let fromBed = simd_distance(spot, SIMD2(Self.bedSpot.x, Self.bedSpot.z))
    let off = min(max((fromBed - 0.1) / 0.1, 0), 1)
    let height = Self.bedSpot.y + (Self.wallSpot.y - Self.bedSpot.y) * off
    return SIMD3(spot.x, height, spot.y)
  }

  /// Whether the note rides in the cat's mouth to the wall, for this delivery.
  private var carriesNote: Bool {
    !reduceMotion && world.activity == .delivering
  }

  /// The part of the delivery spent at the wall, taping the note up.
  private static let taping = 3.4..<5.0
  private static let batGap = 2.5
  private static let greetReach: Float = 0.45
  private static let runSpeed: Float = 0.5

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

  /// The floor point under a finger at `point`, for a view of `size`, both in points.
  func floorPoint(under point: SIMD2<Float>, in size: SIMD2<Float>) -> SIMD2<Float>? {
    NookiFloorRay.floorPoint(
      under: point, viewSize: size, camera: camera.position, target: NookiCamera.target,
      verticalFieldOfView: Self.fieldOfView)
  }

  /// A piece was set down at `box`. The cat looks up and stirs if it lands close by.
  func noticePiece(at box: DecorBox) {
    let landed = SIMD3(box.centre.x, 0, box.centre.y)
    let bed = SIMD3(Self.bedSpot.x, 0, Self.bedSpot.z)
    guard simd_distance(landed, bed) < Self.noticeDistance else { return }
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

  /// Keeps the whole room in a view of `size`, in points.
  func fit(to size: SIMD2<Float>) {
    fittedSize = size
    camera.fit(to: size, fills: fillsView)
    aimLens()
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
      behaviour.react(.tap, at: clock)
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

  /// Turns the cat's whole body towards a tapped object for a moment. No clip turns the head alone.
  private func lookTowards(_ target: NookiTarget) {
    guard !reduceMotion, target != .cat, let holder = holders[target] ?? noteHolder(target) else {
      return
    }
    look(at: holder.position(relativeTo: nil))
  }

  private func look(at point: SIMD3<Float>) {
    let offset = point - catHolder.position(relativeTo: nil)
    let facing = atan2(-offset.x, -offset.z)
    let turn = remainder(facing - NookiChoreography.restHeading, 2 * .pi)
    lookGoal = min(max(turn, -Self.lookLimit), Self.lookLimit)
    lookStart = clock
  }

  private func noteHolder(_ target: NookiTarget) -> Entity? {
    target == .note ? note : nil
  }

  // MARK: - Direction

  /// Plays the opening the host asks for: a new id starts one once the room is on screen, and a
  /// skip jumps to its end. Reduce Motion starts it at its end.
  func flyIn(_ request: PetSceneFlyIn?) {
    guard let request else { return }
    if let opening, opening.id == request.id {
      if request.isSkipped { skipFlight() }
      return
    }
    if pendingFlyIn?.id == request.id, !request.isSkipped { return }
    pendingFlyIn = request
  }

  private func startFlight(_ request: PetSceneFlyIn) {
    opening = SceneFlight(id: request.id, clock: clock, atEnd: reduceMotion || request.isSkipped)
    onOpeningStarted?()
    if reduceMotion || request.isSkipped {
      settleFlight()
    } else {
      lampLevel = 0
      lightsLevel = 0
      noteReveal = 0
    }
    stepFlight()
  }

  private func skipFlight() {
    opening?.skip(at: clock)
    settleFlight()
    stepFlight()
  }

  /// What the end of an opening leaves: lights up, note shown, the cat awake and looking.
  private func settleFlight() {
    lightsLevel = 1
    noteReveal = 1
    cue(.lookAtCamera)
  }

  private func stepFlight() {
    guard var opening else { return }
    let time = opening.time(at: clock)
    let offset = FlyInTimeline.offset(at: time)
    camera.fly(yaw: offset.yaw, pitch: offset.pitch, distance: offset.distance)
    aimLens()
    lightsLevel = Float(FlyInTimeline.lights(at: time))
    noteReveal = Float(FlyInTimeline.note(at: time))
    applyAmbient()
    for cue in opening.dueCues(at: clock) { self.cue(cue) }
    guard opening.isOver(at: clock) else {
      self.opening = opening
      return
    }
    self.opening = nil
    onOpeningEnded?()
  }

  /// Plays a cue with the cat's own clips. Looking at the camera lets go of any finger, so the
  /// head turns to the lens.
  func cue(_ cue: CatCue) {
    behaviour.cue(cue, at: clock)
    if cue == .lookAtCamera { gazePoint = nil }
  }

  /// Turns the cat's head to follow a finger at `point`, in a view of `size` points.
  func gaze(at point: CGPoint?, in size: SIMD2<Float>) {
    guard let point else { return }
    followFinger(at: SIMD2(Float(point.x), Float(point.y)), in: size)
  }

  /// Lights the room for the hour, and shows the partner's sky in the window. `nil` puts back
  /// the room's own evening light.
  func show(dayLight: PetSceneDayLight?) {
    guard dayLight != self.dayLight else { return }
    self.dayLight = dayLight
    let look = dayLight.map { RoomDayLook($0.here) }
    if let look { lampIsOn = look.lampOn }
    var sun = DirectionalLightComponent(
      color: Tone.evening.color, intensity: Self.sunIntensity)
    if let look {
      sun = DirectionalLightComponent(
        color: look.sunColour.platformColour, intensity: look.sunIntensity)
    }
    sunLight.components.set(sun)
    applyAmbient()
    windowPane?.model?.materials = [windowGlass]
  }

  /// The diorama has a lamp and a lantern of its own, so its night goes darker than the shared
  /// look and leaves them to light the room.
  static func ambientShift(_ look: RoomDayLook, phase: DayLight.Phase) -> Float {
    phase == .night ? look.ambientShift + nightDarkening : look.ambientShift
  }

  private static let nightDarkening: Float = -1

  private func applyAmbient() {
    guard var ambient = ambientLight?.components[ImageBasedLightComponent.self] else { return }
    let day = dayLight.map { Self.ambientShift(RoomDayLook($0.here), phase: $0.here.phase) } ?? 0
    let exponent = Self.ambientExponent + day + Self.darkAmbientShift * (1 - lightsLevel)
    guard ambient.intensityExponent != exponent else { return }
    ambient.intensityExponent = exponent
    ambientLight?.components.set(ambient)
    let base = dayLight.map { RoomDayLook($0.here).sunIntensity } ?? Self.sunIntensity
    sunLight.components[DirectionalLightComponent.self]?.intensity = base * lightsLevel
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
    if ScenePerf.isOn, !isAnnounced {
      isAnnounced = true
      ScenePerf.shown(
        ScenePerf.Scene(
          name: "nooki room",
          orbit: { [weak self] in self?.orbit(byX: $0, y: $1) },
          zoom: { [weak self] in self?.zoom(by: $0) },
          release: { [weak self] in self?.endOrbit(velocityX: 0, velocityY: 0) },
          census: { [weak self] in self.map { SceneCensus.of($0.root) } ?? "" }))
    }
    clock += delta
    idleDelta += delta
    if let pendingFlyIn {
      self.pendingFlyIn = nil
      startFlight(pendingFlyIn)
    }
    guard isBusy || idleDelta >= Self.idleStep else { return }
    let step = idleDelta
    idleDelta = 0
    stepFlight()
    stepTilt(Float(step))
    stepYarn(step)
    stepToys(step)
    renovation.step(Float(step), reduceMotion: reduceMotion)
    if !camera.isAtRest {
      camera.step(Float(step))
      aimLens()
    }
    stepMoments()
    apply(elapsed: clock - stepStart, delta: Float(step))
  }

  /// True while something should move at full rate. A sleeping room runs at the idle step.
  private var isBusy: Bool {
    !camera.isAtRest || renovation.isMoving || tilt.isMoving || tilt.pull != .zero
      || yarnPlay.isPlaying || isPlayingWithToys
      || ballSpeed > NookiYarnPlay.noticeSpeed / 2 || world.activity != .sleeping || petStart != nil
      || !wobbles.isEmpty
      || lookStart != nil || lookTurn != 0 || opening != nil || trip != nil || purr.isPurring
      || !purr.hearts.isEmpty || greetPending
      || noteOpening != (noteIsOpen ? 1 : 0) || light != (world.partnerHere ? 1 : 0)
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
    tripPose = nil
    if let (pose, held) = stepHeld() {
      frame.heading = pose.heading
      frame.wake = 1
      frame.eyesOpen = true
      frame.hop = 0
      frame.stretch = 0
      awaySpot = held
      tripPose = pose
    } else if let pose = stepPursuit() {
      frame.heading = pose.heading
      frame.wake = 1
      frame.eyesOpen = true
      frame.hop = 0
      frame.stretch = 0
      awaySpot = tripSpot(pose.spot)
      tripPose = pose
    } else if let trip {
      let pose = trip.pose(at: clock)
      if pose.isDone {
        self.trip = nil
      } else {
        frame.heading = pose.heading
        frame.wake = 1
        frame.eyesOpen = true
        frame.hop = 0
        frame.stretch = 0
        awaySpot = tripSpot(pose.spot)
        tripPose = pose
      }
    }
    let taping = carriesNote && Self.taping.contains(shownTime)
    if taping {
      frame.hop = 0
      frame.heading = 2 * .pi
    }
    applyBody(frame, awaySpot: awaySpot, delta: delta)
    applyClip(frame, taping: taping)
    applyHolders()
    applyLamp(delta)
    applyBowl(delta)
    applyNote(frame, elapsed: elapsed, delta: delta)
  }

  private func applyBody(_ frame: NookiFrame, awaySpot: SIMD3<Float>?, delta: Float) {
    if let lookStart, clock - lookStart >= NookiMotion.lookLength {
      self.lookStart = nil
    }
    let goal = lookStart == nil ? 0 : lookGoal
    lookTurn = Self.eased(lookTurn, to: goal, rate: 7, delta: delta, snap: reduceMotion)

    if !NookiClip.walksWithRig {
      let upright = 0.1 * frame.stretch
      let wide = -0.05 * frame.stretch
      catHolder.scale = [1 + wide, 1 + upright, 1 + wide]
    }

    var spot = mix(Self.bedSpot, Self.wallSpot, t: frame.walk)
    let drop = min(frame.walk / Self.bedDrop, 1)
    spot.y = Self.bedSpot.y + (Self.wallSpot.y - Self.bedSpot.y) * drop
    if let awaySpot { spot = awaySpot }
    let lift = 0.02 * frame.wake + 0.05 * frame.hop + 0.07 * frame.stepHeight
    catHolder.position = spot + [0, lift, 0]
    if frame.light != light { easeLight(to: frame.light, delta: delta) }
    hands.stepLean(delta, reduceMotion: reduceMotion)
    catHolder.orientation =
      simd_quatf(angle: frame.heading + lookTurn + Self.windowTurn * light, axis: [0, 1, 0])
      * simd_quatf(angle: hands.lean, axis: [0, 0, 1])
  }

  private func applyClip(_ frame: NookiFrame, taping: Bool) {
    let clip = NookiClip.choose(frame: frame, yarn: yarnPlay.phase)
    var travel = yarnPlay.isPlaying ? yarnPlay.travelSpeed : Self.walkPace
    var mode = Self.mode(for: clip, yarn: yarnPlay.phase)
    var rate: Float = 1
    if let tripPose {
      mode = .fixed(tripPose.action)
      travel = tripPose.speed
    } else if taping {
      mode = .fixed(behaviour.playable(.reachUp))
      rate = Self.tapingRate
    }
    let beat = behaviour.beat(at: clock, mode: mode)
    rig?.play(
      beat.action, rate: beat.action == .walk ? NookiClip.walkRate(forTravelAt: travel) : rate)
    if clock > gazeUntil { gazePoint = nil }
    rig?.look(
      at: gazePoint ?? lens.position(relativeTo: nil),
      weight: Float(
        CatBehaviour.lookWeight(for: beat, holding: gazePoint != nil, reduceMotion: reduceMotion)))
  }

  /// How much say the room's choreography leaves the cat's own behaviour. Asleep it naps and
  /// wakes as it likes; woken and resting it idles; anything the room is doing it plays as told.
  static func mode(for clip: NookiClip, yarn: NookiYarnPlay.Phase) -> CatBehaviour.Mode {
    switch (clip, yarn) {
    case (.sleep, .resting): .free
    case (.idle, .resting), (.sit, .resting): .awake
    default: .fixed(CatAction(rawValue: clip.rawValue) ?? .idle)
    }
  }

  // MARK: - The cat's attention

  /// How long the head stays on a finger after it last moved.
  private static let fingerLookLength = 1.5

  /// Turns the head and neck, not the body, towards `point` for `length` seconds.
  func headLook(at point: SIMD3<Float>, for length: Double) {
    gazePoint = point
    gazeUntil = clock + length
  }

  /// Turns the cat's head towards a finger at `point`, in a view of `size`, both in points.
  func followFinger(at point: SIMD2<Float>, in size: SIMD2<Float>) {
    guard size.x > 0, size.y > 0 else { return }
    let ray = simd_normalize(
      NookiFloorRay.direction(
        under: point, viewSize: size, camera: camera.position, target: NookiCamera.target,
        verticalFieldOfView: Self.fieldOfView))
    let head = catHolder.position(relativeTo: nil) + [0, 0.18, 0]
    let reach = simd_dot(head - camera.position, ray)
    headLook(at: camera.position + ray * max(reach, 0.5), for: Self.fingerLookLength)
  }

  /// A stroke along the cat at `point` on screen: it leans into the hand and purrs, with hearts
  /// rising from under the finger, as the spot and the way of the fur deserve. A long pet rolls
  /// it onto its back, where a belly rub may get grabbed.
  func stroke(at point: CGPoint) -> [PetSceneEvent] {
    let fresh = petStart == nil
    petStart = petStart ?? clock
    strokePoint = point
    if purr.touch(at: clock, cat: point), trip == nil {
      behaviour.react(.roll, at: clock)
      rollingUntil = clock + behaviour.length(of: behaviour.playable(.rollOver), held: 3)
      hands.onBackUntil = rollingUntil
    }
    var events: [PetSceneEvent] = fresh ? [.petted] : []
    if let body = catBody(), let response = hands.stroke(to: point, on: body, at: clock) {
      events += show(response)
    }
    return events
  }

  func strokeEnded() { hands.endStroke() }

  /// The cat as drawn now, for finding where a finger is on it.
  func catBody() -> CatBodyOnScreen? {
    let size = CGSize(width: CGFloat(fittedSize.x), height: CGFloat(fittedSize.y))
    let forward = catHolder.orientation(relativeTo: nil).act([0, 0, -1])
    let length =
      catLength
      ?? {
        let bounds = catHolder.visualBounds(relativeTo: nil)
        let length = bounds.isEmpty ? 0.3 : max(bounds.extents.x, bounds.extents.z)
        catLength = length
        return length
      }()
    return CatBodyOnScreen.of(
      base: catHolder.position(relativeTo: nil), heading: atan2(-forward.x, -forward.z),
      length: length, isOnBack: hands.isOnBack(at: clock), anatomy: rig?.anatomy ?? .madeCat
    ) {
      GenzCamera.project(
        $0, from: camera.position, towards: NookiCamera.target, fieldOfView: Self.fieldOfView,
        in: size)
    }
  }

  /// A treat landed: it eats, then is pleased.
  func reactToTreat() {
    behaviour.react(.treat, at: clock)
  }

  /// Shows `choice`. A different cat is loaded in place of the one on show, without rebuilding
  /// the room; the old one stays until the new one is ready.
  func setCat(_ choice: CatChoice) {
    guard choice != catChoice else { return }
    catChoice = choice
    guard catLoading != nil else { return }
    catLoading = Task { await loadCat() }
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
      Self.lampIntensity * lampLevel * flicker * lightsLevel
    let lanternFlicker = NookiMotion.flicker(clock + 1.7, reduceMotion: reduceMotion)
    lanternLight.components[PointLightComponent.self]?.intensity =
      Self.lanternIntensity * lanternFlicker * lightsLevel
    guard lampLevel != goal || shownLightsLevel != lightsLevel else { return }
    lampLevel = Self.eased(lampLevel, to: goal, rate: 6, delta: delta, snap: reduceMotion)
    shownLightsLevel = lightsLevel
    for part in lampParts {
      guard var material = part.model.model?.materials[part.material] as? PhysicallyBasedMaterial
      else { continue }
      material.emissiveIntensity = part.glow * (0.05 + 0.95 * lampLevel * lightsLevel)
      part.model.model?.materials[part.material] = material
    }
  }

  private func applyBowl(_ delta: Float) {
    let goal = max(toys.meal ?? 0, play.treat.bowlFill)
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
      at: elapsed, cat: catHolder.position + [0, Self.carryHeight, 0])
    plane.show(pose)
    look(at: pose.position)
    lookStart = clock
  }

  private func applyNote(_ frame: NookiFrame, elapsed: Double, delta: Float) {
    noteOpening = Self.eased(
      noteOpening, to: noteIsOpen ? 1 : 0, rate: 8, delta: delta, snap: reduceMotion)
    note.isEnabled = frame.note > 0 && noteReveal > 0.01
    let inMouth =
      carriesNote ? rig?.mouth().flatMap { note.parent?.convert(position: $0, from: nil) } : nil
    let carried = inMouth ?? catHolder.position + [0, Self.carryHeight, 0]
    let hanging = mix(mix(Self.noteStart, carried, t: frame.note), Self.noteHome, t: frame.pinned)
    let toLens = simd_normalize(NookiCamera.target - camera.position)
    let reading = camera.position + toLens * Self.noteReadingDistance
    note.position = mix(hanging, reading, t: noteOpening)
    let hangingScale =
      inMouth == nil ? 0.3 + 0.25 * frame.note + 0.45 * frame.pinned : 0.22 + 0.78 * frame.pinned
    note.scale =
      .one * (hangingScale + (Self.noteReadingScale - hangingScale) * noteOpening) * noteReveal
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

  private func easeLight(to target: Float, delta: Float) {
    let toward = target - light
    let step = reduceMotion ? abs(toward) : Self.lightPerSecond * delta
    light = abs(toward) <= step ? target : light + (toward < 0 ? -step : step)
    windowLight.components.set(
      PointLightComponent(color: Tone.glow.color, intensity: 900 * light, attenuationRadius: 1.2))
    windowPane?.model?.materials = [windowGlass]
  }

  /// The pane lit by the partner's lamp, or by their sky when the room follows the time of day.
  private var windowGlass: PhysicallyBasedMaterial {
    guard let theirs = dayLight?.theirs else { return Self.glass(light: light) }
    let sky = RoomDayLook.sky(theirs)
    var material = Self.clay(.night)
    material.emissiveColor = .init(color: sky.colour.platformColour)
    // The partner's lamp only tints their sky a little, so the hour still reads.
    material.emissiveIntensity = sky.glow * (1 + 0.3 * light)
    return material
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
    room.addChild(renovation.decor.marker)
    renovation.addFixed(centre: [Self.bedSpot.x, Self.bedSpot.z], half: [0.28, 0.28])
    renovation.addFixed(centre: [Self.bowlPosition.x, Self.bowlPosition.z], half: [0.1, 0.1])
    streakMarks.position = [0.2, 0.72, -0.597]
    room.addChild(streakMarks)
    buildWindow()
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

  /// A small window on the back wall. Its pane glows and a light spills into the room while the
  /// partner is here.
  private func buildWindow() {
    let frame = ModelEntity(
      mesh: .generateBox(size: [0.25, 0.3, 0.014], cornerRadius: 0.004),
      materials: [Self.clay(.walnut)])
    frame.position = Self.windowCentre + [0, 0, 0.004]
    room.addChild(frame)
    let pane = ModelEntity(
      mesh: .generateBox(width: 0.21, height: 0.26, depth: 0.004),
      materials: [windowGlass])
    pane.position = Self.windowCentre + [0, 0, 0.013]
    root.addChild(pane)
    windowPane = pane
    windowLight.position = Self.windowCentre + [0, 0, 0.25]
    root.addChild(windowLight)
  }

  private static func glass(light: Float) -> PhysicallyBasedMaterial {
    var material = clay(.night)
    material.emissiveColor = .init(color: Tone.glow.color)
    material.emissiveIntensity = 2.5 * light
    return material
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
        renovation.register(item.name, holder: holder, half: item.unturnedFootprint(size))
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

  static func makeTappable(
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

  // MARK: - Cat

  /// Starts the cat ahead of the furniture, on its own task so that a slow cat cannot hold up the
  /// room. The cat is reported missing on failure, or at the deadline if the load is still going;
  /// a late arrival clears that.
  private func startLoadingCat() {
    catLoading = Task { await loadCat() }
    let deadline = catDeadline
    Task { [weak self] in
      try? await Task.sleep(for: deadline)
      self?.reportCatIfAbsent()
    }
  }

  private func loadCat() async {
    do {
      let wanted = catChoice
      let (model, shown) = try await loadCatFor(wanted)
      // A newer choice has its own load on the way.
      guard wanted == catChoice || shownCat == nil else { return }
      guard let offset = Self.catOffset(model.visualBounds(relativeTo: nil)) else {
        throw NookiLoadError.noGeometry("Cat")
      }
      // Every cat comes out as long as the standard one: Nooki's furniture is sized to it.
      let anatomy = shown.model.anatomy
      let fit = CatChoice.standard.model.anatomy.length / anatomy.length
      model.scale = .one * Self.catScale * fit
      model.position = offset * fit
      let rig = CatRig(model: model, clips: CatCatalog.clips(shown.model), anatomy: anatomy)
      if let palette = CatCatalog.palette(shown.model, coat: shown.coat) { rig?.paint(palette) }
      let action = self.rig?.current ?? .sleep
      catModel?.removeFromParent()
      catModel = model
      self.rig = rig
      shownCat = shown
      behaviour = CatBehaviour(clips: rig?.info ?? [:], seed: UInt64.random(in: 1...UInt64.max))
      behaviour.follow(play.life ?? LifeDrive())
      rig?.play(rig?.info[action] != nil ? action : .sleep, blend: 0)
      catHolder.addChild(model)
      catLength = nil
      hasCat = true
      NookiTrace.mark("Cat placed")
      setCatMissing(false)
    } catch {
      Self.log.error("\(String(describing: error), privacy: .public)")
      setCatMissing(true)
    }
  }

  private func reportCatIfAbsent() {
    if !hasCat { setCatMissing(true) }
  }

  /// The model for `choice`, or the standard cat when that one will not load, with the choice it
  /// really shows.
  static func loadCatModel(_ choice: CatChoice) async -> (Entity, CatChoice)? {
    if let model = await NookiAssets.compiledCat(choice.model) { return (model, choice) }
    guard choice != .standard, let model = await NookiAssets.compiledCat(CatChoice.standard.model)
    else { return nil }
    return (model, .standard)
  }

  /// Where the model goes so that it sits centred on its own floor, or nil for bounds that hold
  /// nothing a viewer could see.
  static func catOffset(_ bounds: BoundingBox) -> SIMD3<Float>? {
    let corners = [bounds.min, bounds.max]
    guard !bounds.isEmpty, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    else { return nil }
    return -[bounds.center.x, bounds.min.y, bounds.center.z] * catScale
  }

  /// A crossed-out card on the bed, so a cat that failed to load cannot pass for an empty room.
  private func setCatMissing(_ missing: Bool) {
    guard missing != isCatMissing else { return }
    isCatMissing = missing
    missingMark.removeFromParent()
    if missing {
      if missingMark.children.isEmpty { buildMissingMark() }
      catHolder.addChild(missingMark)
    }
    onCatMissing?(missing)
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

  /// Calls `body` with the room's ambient light once it exists, for entities kept outside the room.
  func whenAmbientIsReady(_ body: @escaping (ImageBasedLightReceiverComponent) -> Void) {
    if let ambientReceiver { body(ambientReceiver) } else { onAmbient = body }
  }

  static func ambientEnvironment() async -> EnvironmentResource? {
    guard let image = ambientGradient() else { return nil }
    return try? await EnvironmentResource(equirectangular: image)
  }

  private func addLighting(environment: EnvironmentResource?) {
    if let environment {
      let ambient = Entity()
      ambient.components.set(
        ImageBasedLightComponent(
          source: .single(environment), intensityExponent: Self.ambientExponent))
      room.addChild(ambient)
      ambientLight = ambient
      let receiver = ImageBasedLightReceiverComponent(imageBasedLight: ambient)
      Self.visit(room) { $0.components.set(receiver) }
      ambientReceiver = receiver
      onAmbient?(receiver)
      onAmbient = nil
    }

    let sun = sunLight
    sun.components.set(
      DirectionalLightComponent(color: Tone.evening.color, intensity: Self.sunIntensity))
    sun.components.set(DirectionalLightComponent.Shadow(maximumDistance: 4, depthBias: 2))
    sun.look(at: .zero, from: [1.8, 1.5, 0.7], relativeTo: nil)
    room.addChild(sun)

    lanternLight.position = [0.54, 0.34, 0.42]
    lanternLight.components.set(
      PointLightComponent(
        color: Tone.evening.color, intensity: Self.lanternIntensity, attenuationRadius: 0.8))
    room.addChild(lanternLight)

    // Day light asked for before the lights existed is put on them now.
    if let dayLight {
      self.dayLight = nil
      show(dayLight: dayLight)
    }

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

  static func visit(_ entity: Entity, _ body: (Entity) -> Void) {
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
  case honey, plaster, walnut, ink, paper, heart, lamp, evening, ceiling, bounce, night, glow

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
    case .night: (0.12, 0.16, 0.26)
    case .glow: (1, 0.82, 0.5)
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

  /// Half the floor this piece takes up before it is turned, for a model of `size`.
  func unturnedFootprint(_ size: SIMD3<Float>) -> SIMD2<Float> {
    SIMD2(size.x, size.z) / 2 * Self.standingShare
  }

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
