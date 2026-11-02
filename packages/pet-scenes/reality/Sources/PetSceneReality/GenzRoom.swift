import CoreGraphics
import Foundation
import OSLog
import Observation
import Pet
import PetScene
import RealityKit
import SwiftUI

/// What the flat layers and the host need from a styled room, in the view's points. Changes only
/// when the camera moves, the view resizes, or something happens in the room; the layers' own
/// motion runs off `openedAt`.
@MainActor
@Observable
final class GenzRoomScreen {
  /// When the opening started, or `nil` while the room is still dark and loading.
  var openedAt: Date?
  /// When the latest note landed, for the moment of warmth after it.
  var landedAt: Date?
  var lampOn = true
  var outlines: [RoomLayerSlot: [CGPoint]] = [:]
  /// Just above the cat, or `nil` before the room has been fitted.
  var cat: CGPoint?
  var parallax = CGSize.zero

  func time(at date: Date) -> Double {
    openedAt.map { date.timeIntervalSince($0) } ?? 0
  }

  func state(for slot: RoomLayerSlot, at date: Date) -> RoomLayerState {
    RoomLayerState(
      time: time(at: date), parallax: parallax, outline: outlines[slot] ?? [],
      warmth: GenzOpening.warmth(sinceLanding: landedAt.map { date.timeIntervalSince($0) }),
      lampOn: lampOn)
  }
}

/// The cat models, each loaded once from the room's own files and cloned into each styled room.
/// A cat that will not load is replaced by Mochi, so a room always has one.
@MainActor
final class GenzCatSource {
  private var loading: [CatModel: Task<Entity?, Never>] = [:]
  private let load: NookiModelLoader

  init(load: NookiModelLoader? = nil) {
    let assets = NookiAssets()
    self.load = load ?? { name throws(NookiLoadError) in try await assets.model(name) }
  }

  /// A fresh copy of the model for `choice`, and the choice it really shows.
  func cat(_ choice: CatChoice = .standard) async -> (Entity, CatChoice)? {
    if choice.model != .mochi, let model = await task(choice.model).value {
      return (model.clone(recursive: true), choice)
    }
    guard let mochi = await task(.mochi).value else { return nil }
    return (mochi.clone(recursive: true), .standard)
  }

  private func task(_ model: CatModel) -> Task<Entity?, Never> {
    if let task = loading[model] { return task }
    let load = load
    let task =
      model == .mochi
      ? Task { try? await load(NookiAssets.mochiName) }
      : Task { await NookiAssets.compiledCat(model) }
    loading[model] = task
    return task
  }
}

/// The styled rooms of one scene, each kept once built, sharing meshes, materials and the cat.
@MainActor
final class GenzRoomCache {
  let kit = GenzKit()
  private(set) lazy var cats = GenzCatSource()
  private var rooms: [RoomStyle: GenzRoom] = [:]

  nonisolated init() {}

  func room(_ layout: GenzLayout) -> GenzRoom {
    if let room = rooms[layout.style] { return room }
    let room = GenzRoom(layout: layout, kit: kit, cats: cats)
    rooms[layout.style] = room
    return room
  }

  /// Returns once no styled room is left in a RealityView's scene, or after a few seconds. A
  /// RealityView that mounts while another still has its scene can stay empty for good, so the
  /// next room's view mounts only after this.
  func untilLetGo() async {
    let deadline = ContinuousClock.now + Self.longestTeardown
    while rooms.values.contains(where: { $0.root.scene != nil }), ContinuousClock.now < deadline {
      try? await Task.sleep(for: Self.teardownCheck)
    }
    try? await Task.sleep(for: Self.settle)
  }

  private static let teardownCheck = Duration.milliseconds(50)
  private static let settle = Duration.milliseconds(100)
  private static let longestTeardown = Duration.seconds(5)
}

/// One styled room and everything that moves in it. Built from simple shapes in code, so it is
/// ready a moment after it is asked for; only the cat loads from a file.
@MainActor
final class GenzRoom {
  static let catName = "genz-cat"
  static let noteName = "genz-note"
  static let lampName = "genz-lamp"
  static let lensName = "genz-lens"
  static let bulbName = "genz-bulb"
  static let posterName = "genz-poster"

  let layout: GenzLayout
  let root = Entity()
  let screen = GenzRoomScreen()
  var art: any RoomLayerArt = GenzNativeArt()
  private(set) var camera: GenzCamera
  private(set) var isBuilt = false
  private(set) var hasCat = false

  private let kit: GenzKit
  private let cats: GenzCatSource
  private let room = Entity()
  private let lens = PerspectiveCamera()
  private let catHolder = Entity()
  /// The cat moments switched on in Labs.
  private(set) var moments: Set<CatMoment> = []
  /// The purr and its hearts, for the view to draw.
  let purr = CatPurr()
  private var trip: CatTrip?
  private var tripKind: CatTripKind?
  private var playClock = CatPlayClock(seed: UInt64.random(in: 1...UInt64.max))
  private var lastBat = -Double.infinity
  private var greetPending = false
  private var lastSeenSaved = -Double.infinity
  /// The scale the cat model is shown at, for matching its walk to how fast it moves.
  private var catScale: Float = 1
  /// A dot of lamp light on the cat's floor, for it to chase.
  private let lightDot = ModelEntity()
  private let note = Entity()
  private var notePaper: ModelEntity?
  private var noteTexture: TextureResource?
  private var discModel: ModelEntity?
  private var discTexture: TextureResource?
  private var posterModel: ModelEntity?
  private var posterTexture: TextureResource?
  private var leds: [ModelEntity] = []
  private var lenses: [ModelEntity] = []
  private var shades: [ModelEntity] = []
  private let lampLight = Entity()
  private let outsideLight = Entity()
  private let fillLight = Entity()
  private let headlight = Entity()
  private var rig: CatRig?
  private var behaviour = CatBehaviour(clips: [:])
  private var catChoice = CatChoice.standard
  private var catModel: Entity?
  private var catLoad: Task<Void, Never>?
  private var gazePoint: SIMD3<Float>?
  private var gazeUntil = 0.0
  private var building: Task<Void, Never>?
  private var subscription: EventSubscription?
  private var viewSize = CGSize(width: 393, height: 852)
  private var clock = 0.0
  private var openedClock: Double?
  private var noteClock = 0.0
  private var landedClock: Double?
  private var petClock: Double?
  private var lampOn = true
  private var reduceMotion = false
  private var world = PetWorld()
  private var shownDrawing: CGImage?
  private var settlingFrames = 4
  private var isOnScreen = false
  private var viewsShowing = Set<UUID>()
  private var lastTexture = -1.0
  private var lastLevels: [String: Double] = [:]
  private var tapTimer = NookiTapTimer()
  private var texturesBeingMade = Set<String>()
  private var pendingFlyIn: PetSceneFlyIn?
  private var opening: SceneFlight?
  private var tiltSource: (any NookiTiltSource)?
  private var tilt = NookiTilt()
  private var ambientLight: Entity?
  private let dayLamp = Entity()
  /// Called when an opening asked for through ``flyIn(_:)`` is over.
  var onOpeningEnded: (() -> Void)?
  private var dayLight: PetSceneDayLight?

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "GenzRoom")
  private static let orbitPerPoint: Float = 0.004
  private static let discPixels = 512
  private static let posterPixels = 128
  private static let textureStep = 1.0 / 15
  /// The poster's sun turns slowly, so a few updates a second are enough.
  private static let posterStep = 0.25
  private static let petLength = 4.0
  private static let parallaxPoints: CGFloat = 60
  private static let ambientExponent: Float = 1.6

  init(layout: GenzLayout, kit: GenzKit, cats: GenzCatSource) {
    self.layout = layout
    self.kit = kit
    self.cats = cats
    camera = GenzCamera(home: layout.camera)
    lens.camera.fieldOfViewInDegrees = layout.camera.fieldOfView
    root.addChild(room)
    root.addChild(lens)
    room.isEnabled = false
    aimLens()
  }

  // MARK: - Building

  func startBuilding() {
    guard building == nil else { return }
    building = Task { await build() }
  }

  private func build() async {
    for part in layout.shell(kit) { room.addChild(part) }
    for placement in layout.pieces { place(placement) }
    buildLED()
    buildDisc()
    buildNote()
    await Task.yield()
    addLighting()
    buildBackstop()
    buildLightDot()
    catHolder.name = Self.catName
    catHolder.position = layout.cat.spot.scene
    catHolder.orientation = simd_quatf(angle: layout.cat.heading, axis: [0, 1, 0])
    let length = layout.cat.length
    NookiDiorama.makeTappable(
      catHolder, size: [length * 0.8, length * 0.6, length * 0.8], center: [0, length * 0.3, 0])
    room.addChild(catHolder)
    isBuilt = true
    room.isEnabled = isOnScreen
    applyLevels()
    updateScreen()
    await placeCat()
  }

  private func place(_ placement: GenzLayout.Placement) {
    let piece = kit.build(placement.piece)
    let size = placement.piece.kind.size
    piece.position = GenzRoomPoint(-size.x / 2, -size.y / 2, 0).scene
    let holder = Entity()
    holder.position = placement.centre.scene
    holder.orientation = simd_quatf(angle: placement.yaw, axis: [0, 1, 0])
    holder.addChild(piece)
    room.addChild(holder)
    switch placement.piece.kind {
    case .sunsetLamp, .thriftLamp:
      holder.name = Self.lampName
      NookiDiorama.makeTappable(
        holder, size: [size.x + 0.3, size.z + 0.3, size.y + 0.3], center: [0, size.z / 2, 0])
    default: break
    }
    NookiDiorama.visit(piece) { entity in
      guard let model = entity as? ModelEntity else { return }
      switch entity.name {
      case Self.lensName: lenses.append(model)
      case Self.posterName: posterModel = model
      default:
        if placement.piece.kind == .thriftLamp, model.model?.materials.first is UnlitMaterial {
          shades.append(model)
        }
      }
    }
    if let bulb = piece.findEntity(named: Self.bulbName) {
      lampLight.position = bulb.position(relativeTo: room)
    }
  }

  private func buildLED() {
    let thickness: Float = 0.06
    for (start, end) in zip(layout.led, layout.led.dropFirst()) {
      let from = start.scene
      let to = end.scene
      let length = simd_distance(from, to)
      let along = simd_normalize(to - from)
      let model = kit.part(
        kit.box([thickness, thickness, length + thickness]), kit.glow(layout.ledColour),
        at: (from + to) / 2,
        turn: simd_quatf(from: [0, 0, 1], to: along))
      leds.append(model)
      room.addChild(model)
    }
  }

  private func buildDisc() {
    guard let wall = layout.discWall else { return }
    let model = kit.part(
      kit.plane(width: wall.width, height: wall.height), kit.glow(GenzColour(0xFF8A3D), opacity: 0),
      at: wall.centre.scene)
    discModel = model
    room.addChild(model)
  }

  private func buildNote() {
    note.name = Self.noteName
    let panel = layout.note
    let paper = kit.part(
      kit.box([panel.width, panel.height, 0.02]), kit.glow(layout.paper, opacity: 0))
    note.addChild(paper)
    notePaper = paper
    note.position = panel.centre.scene
    note.orientation = simd_quatf(angle: panel.yaw, axis: [0, 1, 0])
    NookiDiorama.makeTappable(note, size: [panel.width, panel.height, 0.2], center: .zero)
    room.addChild(note)
    refreshNoteTexture()
  }

  /// A large collider behind everything, so a tap that misses every object still counts towards a
  /// double tap.
  private func buildBackstop() {
    let backstop = Entity()
    backstop.position = [0, 0, -120]
    NookiDiorama.makeTappable(backstop, size: [400, 400, 0.1], center: .zero)
    lens.addChild(backstop)
  }

  /// Shows `choice` in place of the cat on show, once it has loaded.
  func setCat(_ choice: CatChoice) {
    guard choice != catChoice else { return }
    catChoice = choice
    guard hasCat || catLoad != nil else { return }
    catLoad = Task { await placeCat() }
  }

  private func placeCat() async {
    let wanted = catChoice
    guard let (model, shown) = await cats.cat(wanted) else {
      Self.log.error("No cat for \(self.layout.style.rawValue, privacy: .public)")
      return
    }
    guard wanted == catChoice || !hasCat else { return }
    let bounds = model.visualBounds(relativeTo: nil)
    guard !bounds.isEmpty, bounds.extents.max().isFinite else { return }
    let scale = layout.cat.length / CatCatalog.mochiReach * CatCatalog.fit(shown.model)
    model.scale = .one * scale
    catScale = scale
    model.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
    let rig = CatRig(model: model, clips: CatCatalog.clips(shown.model))
    if let palette = CatCatalog.palette(shown.model, coat: shown.coat) { rig?.paint(palette) }
    let action = self.rig?.current ?? .sleep
    catModel?.removeFromParent()
    catModel = model
    self.rig = rig
    behaviour = CatBehaviour(clips: rig?.info ?? [:], seed: UInt64.random(in: 1...UInt64.max))
    rig?.play(rig?.info[action] != nil ? action : .sleep, blend: 0)
    catHolder.addChild(model)
    if let receiver = ambientReceiver { NookiDiorama.visit(model) { $0.components.set(receiver) } }
    hasCat = true
  }

  // MARK: - Light

  private var ambientReceiver: ImageBasedLightReceiverComponent?

  private func addLighting() {
    let isSunset = layout.style == .sunsetLamp
    if let environment = Self.ambient(
      top: isSunset ? GenzColour(0xE8D8E0) : GenzColour(0xC8D4E8),
      bottom: isSunset ? GenzColour(0xA08890) : GenzColour(0x8090A8))
    {
      let ambient = Entity()
      ambient.components.set(
        ImageBasedLightComponent(
          source: .single(environment), intensityExponent: Self.ambientExponent))
      room.addChild(ambient)
      ambientLight = ambient
      let receiver = ImageBasedLightReceiverComponent(imageBasedLight: ambient)
      NookiDiorama.visit(room) { $0.components.set(receiver) }
      ambientReceiver = receiver
    }
    let lamp = layout.lamp
    if isSunset {
      lampLight.components.set(
        SpotLightComponent(
          color: layout.lampColour.platformColour, intensity: 0, innerAngleInDegrees: 18,
          outerAngleInDegrees: 46, attenuationRadius: 14))
      lampLight.look(at: lamp.aim.scene, from: lamp.at.scene, relativeTo: room)
      fillLight.position = GenzRoomPoint(3.4, 2.4, 2.6).scene
      fillLight.components.set(
        PointLightComponent(
          color: GenzColour(0xFF7A45).platformColour, intensity: 0, attenuationRadius: 9))
      room.addChild(fillLight)
    } else {
      if lampLight.position == .zero { lampLight.position = lamp.at.scene }
      lampLight.components.set(
        PointLightComponent(
          color: layout.lampColour.platformColour, intensity: 0, attenuationRadius: 6))
      headlight.components.set(
        SpotLightComponent(
          color: GenzColour(0xFFF4DD).platformColour, intensity: 0, innerAngleInDegrees: 10,
          outerAngleInDegrees: 28, attenuationRadius: 20))
      room.addChild(headlight)
    }
    room.addChild(lampLight)
    outsideLight.components.set(
      DirectionalLightComponent(
        color: (isSunset ? GenzColour(0x8FA6D8) : GenzColour(0xFFD9A0)).platformColour,
        intensity: 0))
    let middle = GenzRoomPoint(4, 3, 1).scene
    let from = isSunset ? GenzRoomPoint(-8, 3, 7).scene : GenzRoomPoint(4.5, -9, 7).scene
    outsideLight.look(at: middle, from: from, relativeTo: room)
    room.addChild(outsideLight)
    dayLamp.components.set(DirectionalLightComponent(color: .white, intensity: 0))
    dayLamp.look(at: middle, from: from + [0, 4, 0], relativeTo: room)
    room.addChild(dayLamp)
    applyDayLight()
  }

  private static func ambient(top: GenzColour, bottom: GenzColour) -> EnvironmentResource? {
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let gradient = CGGradient(
        colorsSpace: space, colors: [bottom.cgColor, top.cgColor] as CFArray, locations: [0, 1])
    else { return nil }
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 32), options: [])
    guard let image = context.makeImage() else { return nil }
    return try? EnvironmentResource(equirectangular: image)
  }

  // MARK: - Showing the pet

  func show(_ world: PetWorld) {
    let arrived = world.noteArrived && world.step != self.world.step
    self.world = world
    guard arrived else { return }
    landedClock = clock
    screen.landedAt = .now
    noteClock = clock - (layout.style == .sunsetLamp ? 1.05 : 1.1)
    if reduceMotion { noteClock = clock - GenzOpening.length }
    if moments.contains(.carriesNote), !reduceMotion, hasCat {
      // The note is all there from the start: it rides in the cat's mouth until it is taped up.
      noteClock = clock - GenzOpening.length
      startDelivery()
    }
  }

  func show(drawing: CGImage?) {
    guard drawing !== shownDrawing else { return }
    shownDrawing = drawing
    refreshNoteTexture()
  }

  private func noteImage() -> CGImage? {
    let panel = layout.note
    return GenzTextures.note(
      drawing: shownDrawing, paper: layout.paper, aspect: CGFloat(panel.height / panel.width),
      corners: layout.style == .windowSeat)
  }

  private func refreshNoteTexture() {
    guard notePaper != nil, let image = noteImage() else { return }
    if let noteTexture {
      try? noteTexture.replace(withImage: image, options: .init(semantic: .color))
      lastLevels["note"] = nil
      return
    }
    guard !texturesBeingMade.contains("note") else { return }
    texturesBeingMade.insert("note")
    Task {
      let texture = try? await TextureResource(image: image, options: .init(semantic: .color))
      texturesBeingMade.remove("note")
      guard let texture else { return }
      noteTexture = texture
      try? texture.replace(withImage: noteImage() ?? image, options: .init(semantic: .color))
      lastLevels["note"] = nil
      applyLevels()
    }
  }

  func setReduceMotion(_ reduced: Bool) {
    reduceMotion = reduced
    if reduced, let openedClock, clock - openedClock < GenzOpening.length {
      self.openedClock = clock - GenzOpening.length
      screen.openedAt = Date.now.addingTimeInterval(-GenzOpening.length)
    }
  }

  /// Plays the opening again, from the dark.
  func replayOpening() {
    guard openedClock != nil else { return }
    startOpening()
  }

  private func startOpening() {
    let skip = reduceMotion ? GenzOpening.length : 0
    openedClock = clock - skip
    noteClock = clock - skip
    screen.openedAt = Date.now.addingTimeInterval(-skip)
    lastTexture = -1
  }

  // MARK: - Screen

  func setOnScreen(_ onScreen: Bool, in view: UUID) {
    if onScreen { viewsShowing.insert(view) } else { viewsShowing.remove(view) }
    let wasOnScreen = isOnScreen
    isOnScreen = !viewsShowing.isEmpty
    if isOnScreen, !wasOnScreen {
      greetPending = CatGreeting.isDue(lastSeen: CatSeen.last, now: .now)
    }
    if !isOnScreen, wasOnScreen { CatSeen.mark() }
    room.isEnabled = isOnScreen && isBuilt
    if isOnScreen { tiltSource?.start() } else { tiltSource?.stop() }
  }

  func startUpdates(from content: RealityViewCameraContent) {
    subscription?.cancel()
    settlingFrames = 4
    subscription = content.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil) {
      [weak self] event in
      let delta = event.deltaTime
      MainActor.assumeIsolated { self?.tick(delta) }
    }
  }

  func fit(to size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    viewSize = size
    camera.fit(to: SIMD2(Float(size.width), Float(size.height)))
    aimLens()
  }

  // MARK: - Camera and touch

  func orbit(byX deltaX: Float, y deltaY: Float) {
    camera.drag(yaw: -deltaX * Self.orbitPerPoint, pitch: deltaY * Self.orbitPerPoint)
    aimLens()
  }

  func endOrbit(velocityX: Float, velocityY: Float) {
    camera.release(
      yawVelocity: -velocityX * Self.orbitPerPoint, pitchVelocity: velocityY * Self.orbitPerPoint,
      coasting: !reduceMotion)
  }

  func zoom(by scale: Float) {
    camera.zoom(by: scale)
    aimLens()
  }

  func endZoom() {
    camera.release(yawVelocity: 0, pitchVelocity: 0, coasting: false)
  }

  /// What a tap on `entity` does, and the event to report, if any.
  func tap(_ entity: Entity, at time: TimeInterval) -> PetSceneEvent? {
    if tapTimer.isDoubleTap(at: time) {
      camera.goHome(animated: !reduceMotion)
      return nil
    }
    var current: Entity? = entity
    while let found = current {
      switch found.name {
      case Self.catName: return petCat()
      case Self.noteName: return .noteOpened(delivery: world.delivery)
      case Self.lampName:
        toggleLamp()
        return nil
      default: current = found.parent
      }
    }
    return nil
  }

  /// A tap on the cat: its ears perk and its head tilts. Counts as a pet for the pair.
  func petCat() -> PetSceneEvent {
    if trip != nil { return .petted }
    petClock = clock
    behaviour.react(.tap, at: clock)
    return .petted
  }

  func toggleLamp() {
    lampOn.toggle()
    screen.lampOn = lampOn
    lastTexture = -1
  }

  private func aimLens() {
    lens.look(at: camera.target, from: camera.position, relativeTo: nil)
    updateScreen()
  }

  /// Projects what the flat layers follow, and where the cat is, into the view.
  private func updateScreen() {
    let project = { (point: GenzRoomPoint) in self.camera.project(point.scene, in: self.viewSize) }
    let led = layout.led.compactMap(project)
    let window = layout.window.compactMap(project)
    let note = layout.note.corners.compactMap(project)
    var outlines: [RoomLayerSlot: [CGPoint]] = [:]
    switch layout.style {
    case .sunsetLamp:
      outlines[.sunsetBloom] = led
      outlines[.sunsetCity] = window
    case .windowSeat:
      outlines[.windowBloom] = led
      outlines[.windowBacklight] = note
    case .nooki: break
    }
    if screen.outlines != outlines { screen.outlines = outlines }
    let spot = layout.cat.spot
    let cat = project(GenzRoomPoint(spot.x, spot.y, spot.z + layout.cat.length * 0.55))
    if screen.cat != cat { screen.cat = cat }
    let parallax = CGSize(
      width: -CGFloat(camera.turn) * Self.parallaxPoints,
      height: CGFloat(camera.pitch - layout.camera.pitch) * Self.parallaxPoints)
    if screen.parallax != parallax { screen.parallax = parallax }
  }

  // MARK: - Updates

  private func tick(_ delta: TimeInterval) {
    guard isOnScreen, isBuilt else { return }
    clock += delta
    if settlingFrames > 0 {
      settlingFrames -= 1
      if settlingFrames == 0, openedClock == nil { startOpening() }
      return
    }
    if let pendingFlyIn {
      self.pendingFlyIn = nil
      startFlight(pendingFlyIn)
    }
    stepFlight()
    stepTilt(Float(delta))
    if !camera.isAtRest {
      camera.step(Float(delta))
      aimLens()
    }
    stepMoments()
    applyCat()
    applyLevels()
  }

  // MARK: - Direction

  /// Plays the opening the host asks for: the camera flies in over the room's own opening, and
  /// the cat wakes and looks up on cue. A skip, or Reduce Motion, goes straight to the end.
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
    let atEnd = reduceMotion || request.isSkipped
    opening = SceneFlight(id: request.id, clock: clock, atEnd: atEnd)
    startOpening()
    if atEnd { skipFlight() }
    stepFlight()
  }

  private func skipFlight() {
    opening?.skip(at: clock)
    openedClock = clock - GenzOpening.length
    noteClock = openedClock ?? clock
    screen.openedAt = Date.now.addingTimeInterval(-GenzOpening.length)
    lastTexture = -1
    cue(.lookAtCamera)
  }

  private func stepFlight() {
    guard var opening else { return }
    let offset = FlyInTimeline.offset(at: opening.time(at: clock))
    camera.fly(yaw: offset.yaw, pitch: offset.pitch, distance: offset.distance)
    aimLens()
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

  /// Turns the cat's head to follow a finger at `point`.
  func gaze(at point: CGPoint?) {
    guard let point else { return }
    followFinger(at: point)
  }

  /// Leans the camera with the phone while `follows` is true.
  func setFollowsTilt(_ follows: Bool) {
    if follows, tiltSource == nil {
      let source = NookiTiltSources.standard()
      source.start()
      tiltSource = source
    } else if !follows, let source = tiltSource {
      source.stop()
      tiltSource = nil
    }
  }

  private func stepTilt(_ delta: Float) {
    if let gravity = tiltSource?.gravity, !reduceMotion {
      tilt.update(gravity: gravity, delta: delta)
    } else {
      tilt.settle(delta: delta)
    }
    guard tilt.lean != camera.lean else { return }
    camera.lean(to: tilt.lean)
    aimLens()
  }

  /// Lights the room for the hour here. `nil` keeps the room's own night.
  func show(dayLight: PetSceneDayLight?) {
    guard dayLight != self.dayLight else { return }
    self.dayLight = dayLight
    if let here = dayLight?.here, here.lampOn != lampOn { toggleLamp() }
    applyDayLight()
  }

  /// The styled rooms are made for the evening, so daylight only ever adds to their own light;
  /// the night still darkens them.
  static func ambientShift(_ look: RoomDayLook?, phase: DayLight.Phase?) -> Float {
    guard let look else { return 0 }
    return phase == .night ? look.ambientShift : max(look.ambientShift, 0) * 1.5
  }

  private func applyDayLight() {
    let look = dayLight.map { RoomDayLook($0.here) }
    dayLamp.components.set(
      DirectionalLightComponent(
        color: (look?.sunColour ?? .one).platformColour,
        intensity: look.map { $0.sunIntensity * 1.5 } ?? 0))
    guard var ambient = ambientLight?.components[ImageBasedLightComponent.self] else { return }
    ambient.intensityExponent =
      Self.ambientExponent + Self.ambientShift(look, phase: dayLight?.here.phase)
    ambientLight?.components.set(ambient)
  }

  private var openingTime: Double { openedClock.map { clock - $0 } ?? 0 }

  private func applyCat() {
    guard let rig else { return }
    if let petClock, clock - petClock > Self.petLength { self.petClock = nil }
    var mode: CatBehaviour.Mode =
      switch world.activity {
      case .delivering, .settling: .awake
      case .sleeping: .free
      }
    var rate: Float = 1
    if let pose = stepTrip() {
      mode = .fixed(pose.action)
      if pose.action == .walk { rate = walkRate(pose.speed) }
    }
    let beat = behaviour.beat(at: clock, mode: mode)
    rig.play(beat.action, rate: rate)
    if clock > gazeUntil { gazePoint = nil }
    rig.look(
      at: gazePoint ?? lens.position(relativeTo: nil),
      weight: Float(
        CatBehaviour.lookWeight(for: beat, holding: gazePoint != nil, reduceMotion: reduceMotion)))
  }

  /// How long the head stays on a finger after it last moved.
  private static let fingerLookLength = 1.5

  /// Turns the head and neck, not the body, towards `point` for `length` seconds.
  private func headLook(at point: SIMD3<Float>, for length: Double) {
    gazePoint = point
    gazeUntil = clock + length
  }

  /// Turns the cat's head towards a finger at `point` in the view.
  func followFinger(at point: CGPoint) {
    let size = SIMD2(Float(viewSize.width), Float(viewSize.height))
    guard size.x > 0, size.y > 0 else { return }
    let ray = simd_normalize(
      NookiFloorRay.direction(
        under: SIMD2(Float(point.x), Float(point.y)), viewSize: size, camera: camera.position,
        target: camera.target, verticalFieldOfView: camera.fieldOfView))
    let head = catHolder.position(relativeTo: nil) + [0, layout.cat.length * 0.5, 0]
    let reach = simd_dot(head - camera.position, ray)
    headLook(at: camera.position + ray * max(reach, layout.cat.length), for: Self.fingerLookLength)
  }

  /// Whether a finger at `point` is on the cat, for telling a stroke from a turn of the room.
  func isOverCat(_ point: CGPoint) -> Bool {
    guard let cat = screen.cat else { return false }
    return hypot(point.x - cat.x, point.y - cat.y) < 70
  }

  /// A stroke along the cat: eyes close and it purrs. Reports a pet like a tap does.
  func stroke() -> PetSceneEvent? {
    let fresh = petClock == nil
    petClock = clock
    behaviour.react(.pet, at: clock)
    strokeMoved()
    return fresh ? .petted : nil
  }

  /// The finger is still stroking the cat: the purr goes on, and a long pet rolls it over.
  func strokeMoved() {
    guard moments.contains(.purrs), trip == nil else { return }
    if purr.touch(at: clock, cat: screen.cat) { behaviour.react(.roll, at: clock) }
  }

  /// A treat or the partner's pet: the cat reacts without telling anyone.
  func react(_ reaction: CatReaction) {
    petClock = clock
    behaviour.react(reaction, at: clock)
  }

  /// Sets every light, glow and texture for the current moment. Each is only touched when its
  /// level has moved, so a still room costs little.
  private func applyLevels() {
    let time = openingTime
    let warmth = GenzOpening.warmth(sinceLanding: landedClock.map { clock - $0 })
    switch layout.style {
    case .sunsetLamp: applySunset(time, warmth: warmth)
    case .windowSeat: applyWindow(time, warmth: warmth)
    case .nooki: break
    }
  }

  private func changed(_ key: String, _ value: Double, step: Double = 0.01) -> Bool {
    if let last = lastLevels[key], abs(last - value) < step { return false }
    lastLevels[key] = value
    return true
  }

  private func applySunset(_ time: Double, warmth: Double) {
    let led = GenzOpening.sunsetLED(time)
    if changed("led", led) { setLED(led) }
    let click = lampOn ? GenzOpening.lampClick(time) : 0
    let bloom = GenzOpening.discBloom(time) * (lampOn ? 1 : 0)
    if changed("lamp", click + bloom * 10 + warmth * 100, step: 0.02) {
      lampLight.components[SpotLightComponent.self]?.intensity =
        Float(click) * 90_000 * Float(1 + 0.3 * warmth)
      fillLight.components[PointLightComponent.self]?.intensity =
        Float(bloom) * 26_000 * Float(1 + 0.4 * warmth)
      for lens in lenses {
        lens.model?.materials = [kit.glow(GenzColour(0xFFB066).shaded(Float(click) - 1))]
      }
    }
    let moon = GenzOpening.eased(time, from: 0.2, length: 1)
    if changed("moon", moon) {
      outsideLight.components[DirectionalLightComponent.self]?.intensity = Float(moon) * 420
    }
    let breath = GenzOpening.discBreath(time) * (0.92 + 0.08 * warmth)
    if changed("breath", breath, step: 0.02) { setDiscOpacity(breath) }
    let note = GenzOpening.sunsetNote(clock - noteClock)
    if changed("note", note) {
      setNote(opacity: note, tint: 1)
      self.note.orientation = simd_quatf(
        angle: Float(-4 * (1 - note)) * .pi / 180, axis: [0, 0, 1])
    }
    let isChanging = time < 1.8 || warmth > 0
    let wait = isChanging ? Self.textureStep : Self.posterStep
    if lastTexture < 0 || clock - lastTexture >= wait {
      refreshTextures(time: time, warmth: warmth)
    }
  }

  private func applyWindow(_ time: Double, warmth: Double) {
    let street = GenzOpening.streetLamp(time)
    if changed("street", street) {
      outsideLight.components[DirectionalLightComponent.self]?.intensity = Float(street) * 900
    }
    let led = GenzOpening.windowLED(time)
    if changed("led", led, step: 0.05) { setLED(led) }
    let lamp = (lampOn ? GenzOpening.eased(time, from: 1.4, length: 0.8) : 0)
    if changed("lamp", lamp + warmth * 10, step: 0.02) {
      lampLight.components[PointLightComponent.self]?.intensity =
        Float(lamp) * 9_000 * Float(1 + 0.3 * warmth)
      for shade in shades {
        shade.model?.materials = [kit.glow(GenzColour(0xF3E3C3).shaded(Float(lamp) * 0.55 - 0.55))]
      }
    }
    let lit = GenzOpening.windowNote(clock - noteClock) * (0.85 + 0.15 * street)
    if changed("note", lit, step: 0.02) { setNote(opacity: 1, tint: 0.4 + 0.6 * lit) }
    let pass = GenzOpening.headlight(time)
    if changed("headlight", pass ?? -1, step: 0.004) {
      let progress = Float(pass ?? 0)
      let x = -6 + 20 * progress
      headlight.look(
        at: GenzRoomPoint(x + 3, 4, 0.3).scene, from: GenzRoomPoint(x, -7, 2.2).scene,
        relativeTo: room)
      let fade = pass.map { sin(Float($0) * .pi) } ?? 0
      headlight.components[SpotLightComponent.self]?.intensity = reduceMotion ? 0 : fade * 160_000
    }
  }

  private func setLED(_ level: Double) {
    let material = kit.glow(layout.ledColour.shaded(Float(level) * 0.9 - 0.9))
    for led in leds { led.model?.materials = [material] }
  }

  private func setDiscOpacity(_ opacity: Double) {
    guard var material = discModel?.model?.materials.first as? UnlitMaterial, discTexture != nil
    else { return }
    material.blending = .transparent(opacity: .init(floatLiteral: Float(opacity)))
    discModel?.model?.materials = [material]
  }

  private func setNote(opacity: Double, tint: Double) {
    guard let notePaper else { return }
    // A clear paper still hides what is behind it, so it leaves the scene until it starts to show.
    notePaper.isEnabled = opacity > 0.01
    var material = UnlitMaterial()
    let shade = CGFloat(tint)
    if let noteTexture {
      material.color = .init(
        tint: .init(red: shade, green: shade, blue: shade, alpha: 1), texture: .init(noteTexture))
    } else {
      let paper = layout.paper
      material.color = .init(
        tint: .init(
          red: CGFloat(paper.red) * shade, green: CGFloat(paper.green) * shade,
          blue: CGFloat(paper.blue) * shade, alpha: 1))
    }
    if opacity < 1 {
      material.blending = .transparent(opacity: .init(floatLiteral: Float(opacity)))
    }
    notePaper.model?.materials = [material]
  }

  private func refreshTextures(time: Double, warmth: Double) {
    lastTexture = clock
    var state = RoomLayerState(time: time, warmth: warmth, lampOn: lampOn)
    if discModel != nil,
      let image = art.image(for: .sunsetDisc, state: state, pixels: Self.discPixels)
    {
      updateTexture(image, current: discTexture, key: "disc") { texture in
        self.discTexture = texture
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: 1.0)
        self.discModel?.model?.materials = [material]
        self.lastLevels["breath"] = nil
      }
    }
    state.outline = []
    if posterModel != nil,
      let image = art.image(for: .sunsetPoster, state: state, pixels: Self.posterPixels)
    {
      updateTexture(image, current: posterTexture, key: "poster") { texture in
        self.posterTexture = texture
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.roughness = 0.9
        self.posterModel?.model?.materials = [material]
        if let receiver = self.ambientReceiver { self.posterModel?.components.set(receiver) }
      }
    }
  }

  /// Draws `image` into the texture, or makes the texture first. Only one is ever made per `key`.
  private func updateTexture(
    _ image: CGImage, current: TextureResource?, key: String,
    made: @escaping (TextureResource) -> Void
  ) {
    if let current {
      try? current.replace(withImage: image, options: .init(semantic: .color))
      return
    }
    guard !texturesBeingMade.contains(key) else { return }
    texturesBeingMade.insert(key)
    Task {
      let texture = try? await TextureResource(image: image, options: .init(semantic: .color))
      texturesBeingMade.remove(key)
      if let texture { made(texture) }
    }
  }
}

// MARK: - Cat moments

/// Why the cat is away from its place.
enum CatTripKind: Equatable {
  /// Carrying the note to the wall or the glass and taping it up.
  case delivery
  /// Running up to the camera after hours away.
  case greeting
  /// Chasing a dot of lamp light that jumps from `first` to `second`.
  case chase(first: SIMD2<Float>, second: SIMD2<Float>)
}

extension GenzRoom {
  /// Switches the cat moments to `moments`.
  func setMoments(_ moments: Set<CatMoment>) {
    self.moments = moments
    if !moments.contains(.greets) { greetPending = false }
  }

  /// A finger near the edge of the view catches the cat's eye: it looks, then bats at it.
  func bat(at point: CGPoint) {
    guard moments.contains(.batsAtFinger), trip == nil, world.activity == .sleeping,
      clock - lastBat > Self.batGap,
      CatEdge.isNearEdge(x: Double(point.x), width: Double(viewSize.width))
    else { return }
    lastBat = clock
    followFinger(at: point)
    behaviour.react(.bat, at: clock)
  }

  private static var batGap: Double { 2.5 }

  private var home: SIMD2<Float> {
    let spot = layout.cat.spot.scene
    return SIMD2(spot.x, spot.z)
  }

  /// The cat's walking pace and running pace, in metres a second, from its size in this room.
  private var walkSpeed: Float { layout.cat.length * 0.9 }
  private var runSpeed: Float { layout.cat.length * 2.2 }

  /// A spot in front of the cat's place, for it to face when it is back.
  private var homeFront: SIMD2<Float> {
    let heading = layout.cat.heading
    return home + SIMD2(-sin(heading), -cos(heading)) * layout.cat.length
  }

  /// The walk clip's speed for moving at `speed`, at the cat's size here.
  func walkRate(_ speed: Float) -> Float {
    let natural = NookiClip.walkingSpeed * catScale / NookiDiorama.mochiScale
    return min(max(speed / max(natural, 0.001), 0.6), 3)
  }

  /// Starts what the moments do on their own: a greeting after hours away, a chase now and then.
  func stepMoments() {
    purr.tick(at: clock, cat: screen.cat)
    if clock - lastSeenSaved > 30 {
      lastSeenSaved = clock
      CatSeen.mark()
    }
    let isFree =
      trip == nil && world.activity == .sleeping && !reduceMotion && hasCat && opening == nil
    if greetPending, isFree {
      greetPending = false
      startGreeting()
      playClock.postpone(from: clock)
    } else if moments.contains(.chases), isFree, playClock.isDue(at: clock) {
      startChase()
    }
  }

  func startDelivery() {
    let paper = note.position
    let target = SIMD2(paper.x, paper.z)
    let under = CatTrip.towards(
      target, from: home, upTo: layout.cat.length * 2.4, keep: layout.cat.length * 0.45)
    begin(
      .delivery,
      legs: [
        .hold(behaviour.playable(.perk), seconds: 0.6, facing: target),
        .walk(to: under, speed: walkSpeed),
        .hold(behaviour.playable(.reachUp), seconds: 2.2, facing: target),
        .walk(to: home, speed: walkSpeed),
        .hold(behaviour.playable(.sit), seconds: 0.5, facing: homeFront),
      ])
  }

  func startGreeting() {
    let eye = SIMD2(camera.position.x, camera.position.z)
    let near = CatTrip.towards(eye, from: home, upTo: layout.cat.length * 1.6)
    begin(
      .greeting,
      legs: [
        .hold(behaviour.playable(.perk), seconds: 0.7, facing: eye),
        .walk(to: near, speed: runSpeed),
        .hold(behaviour.playable(.headbutt), seconds: 1.8, facing: eye),
        .hold(behaviour.playable(.happy), seconds: 1.4, facing: eye),
        .walk(to: home, speed: walkSpeed),
        .hold(behaviour.playable(.sit), seconds: 0.5, facing: homeFront),
      ])
    gazePoint = camera.position
    gazeUntil = clock + 5
  }

  func startChase() {
    // The dot lands on the cat's own floor, on the side towards the camera, so it is seen.
    let eye = SIMD2(camera.position.x, camera.position.z)
    let towardsEye = CatTrip.heading(from: home, to: eye)
    func spot(_ turn: Float, _ reach: Float) -> SIMD2<Float> {
      let heading = towardsEye + turn
      return home + SIMD2(-sin(heading), -cos(heading)) * layout.cat.length * reach
    }
    let side: Float = Bool.random() ? 1 : -1
    let first = spot(side * Float.random(in: 0.5...1.1), Float.random(in: 1.0...1.4))
    let second = spot(-side * Float.random(in: 0.3...0.9), Float.random(in: 0.9...1.3))
    let keep = layout.cat.length * 0.3
    let pounce = behaviour.playable(.pounce)
    let crouch = behaviour.playable(.crouchWiggle)
    let firstLanding = CatTrip.towards(first, from: home, upTo: 10, keep: keep)
    let secondLanding = CatTrip.towards(second, from: firstLanding, upTo: 10, keep: keep)
    begin(
      .chase(first: first, second: second),
      legs: [
        .hold(behaviour.playable(.look), seconds: 1.0, facing: first),
        .hold(crouch, seconds: 0.9, facing: first),
        .walk(
          to: firstLanding, speed: simd_distance(home, firstLanding) / 1.2, action: pounce),
        .hold(behaviour.playable(.perk), seconds: 0.6, facing: second),
        .hold(crouch, seconds: 0.7, facing: second),
        .walk(
          to: secondLanding, speed: simd_distance(firstLanding, secondLanding) / 1.2,
          action: pounce),
        .hold(behaviour.playable(.happy), seconds: 1.2),
        .walk(to: home, speed: walkSpeed),
        .hold(behaviour.playable(.sit), seconds: 0.5, facing: homeFront),
      ])
  }

  private func begin(_ kind: CatTripKind, legs: [CatTrip.Leg]) {
    let heading = layout.cat.heading
    trip = CatTrip(from: home, heading: heading, legs: legs, at: clock)
    tripKind = kind
  }

  /// Puts the cat, the note and the light dot where the trip has them now. Returns the pose, or
  /// nil when no trip is playing.
  func stepTrip() -> CatTrip.Pose? {
    guard let trip, let tripKind else { return nil }
    let pose = trip.pose(at: clock)
    if pose.isDone {
      endTrip()
      return nil
    }
    let height = layout.cat.spot.scene.y
    catHolder.position = SIMD3(pose.spot.x, height, pose.spot.y)
    catHolder.orientation = simd_quatf(angle: pose.heading, axis: [0, 1, 0])
    let spot = layout.cat.spot
    screen.cat =
      camera.project(
        catHolder.position + [0, layout.cat.length * 0.55, 0], in: viewSize)
      ?? camera.project(GenzRoomPoint(spot.x, spot.y, spot.z).scene, in: viewSize)
    switch tripKind {
    case .delivery: carryNote(pose)
    case .chase(let first, let second): showDot(pose, first: first, second: second)
    case .greeting: break
    }
    return pose
  }

  /// The note rides in the mouth, is pressed onto its place during the reach, and stays there.
  private func carryNote(_ pose: CatTrip.Pose) {
    let panel = layout.note.centre.scene
    let inMouth = rig?.mouth().map { room.convert(position: $0, from: nil) } ?? panel
    let taped: Float =
      switch pose.leg {
      case 0, 1: 0
      case 2: Float(min(max((pose.progress - 0.35) / 0.3, 0), 1))
      default: 1
      }
    let eased = taped * taped * (3 - 2 * taped)
    note.position = inMouth + (panel - inMouth) * eased
    note.scale = .one * (Self.carriedNoteScale + (1 - Self.carriedNoteScale) * eased)
  }

  private static var carriedNoteScale: Float { 0.3 }

  /// The dot sits on the first spot, darts to the second as the cat lands, and fades at the end.
  private func showDot(_ pose: CatTrip.Pose, first: SIMD2<Float>, second: SIMD2<Float>) {
    let height = layout.cat.spot.scene.y + 0.004
    let at: SIMD2<Float>
    var opacity: Float = 0.9
    switch pose.leg {
    case 0:
      at = first
      opacity = 0.9 * Float(min(pose.progress * 3, 1))
    case 1, 2: at = first
    case 3:
      let dart = Float(min(pose.progress * 3, 1))
      at = first + (second - first) * dart
    case 4, 5: at = second
    case 6:
      at = second
      opacity = 0.9 * Float(1 - pose.progress)
    default:
      at = second
      opacity = 0
    }
    lightDot.isEnabled = opacity > 0.01
    lightDot.position = SIMD3(at.x, height, at.y)
    lightDot.components.set(OpacityComponent(opacity: opacity))
    gazePoint = lightDot.position(relativeTo: nil)
    gazeUntil = clock + 0.3
  }

  private func endTrip() {
    if tripKind == .delivery {
      note.position = layout.note.centre.scene
      note.scale = .one
    }
    lightDot.isEnabled = false
    trip = nil
    tripKind = nil
    catHolder.position = layout.cat.spot.scene
    catHolder.orientation = simd_quatf(angle: layout.cat.heading, axis: [0, 1, 0])
    updateScreen()
  }

  func buildLightDot() {
    let radius = layout.cat.length * 0.07
    lightDot.model = ModelComponent(
      mesh: .generateCylinder(height: 0.002, radius: radius),
      materials: [UnlitMaterial(color: .init(red: 1, green: 0.42, blue: 0.3, alpha: 1))])
    lightDot.isEnabled = false
    room.addChild(lightDot)
  }
}
