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
  /// Where the room's lights are in the view, for the glow drawn over them.
  var lights = GlowSpots()
  /// Just above the cat, or `nil` before the room has been fitted.
  var cat: CGPoint?
  var parallax = CGSize.zero
  /// The window's opening as the camera sees it now, and as it sees it from its home place.
  var window: [CGPoint] = []
  var homeWindow: [CGPoint] = []
  /// What the window looks out on, and the hour it is lit for.
  var windowView = WindowViewChoice.standard
  var viewHour = ViewHour.night

  func time(at date: Date) -> Double {
    openedAt.map { date.timeIntervalSince($0) } ?? 0
  }

  func state(for slot: RoomLayerSlot, at date: Date) -> RoomLayerState {
    RoomLayerState(
      time: time(at: date), parallax: parallax, outline: outlines[slot] ?? [],
      warmth: GenzOpening.warmth(sinceLanding: landedAt.map { date.timeIntervalSince($0) }),
      lampOn: lampOn)
  }

  func viewState(at date: Date) -> WindowViewState {
    WindowViewState(
      view: windowView.view, weather: windowView.shownWeather, hour: viewHour,
      time: time(at: date), now: date.timeIntervalSinceReferenceDate, window: window,
      home: homeWindow, lampOn: lampOn)
  }
}

/// The cat models, each loaded once from its compiled file and cloned into each styled room. A
/// cat that will not load is replaced by the standard cat, so a room always has one.
@MainActor
final class GenzCatSource {
  private var loading: [CatModel: Task<Entity?, Never>] = [:]

  /// A fresh copy of the model for `choice`, and the choice it really shows.
  func cat(_ choice: CatChoice = .standard) async -> (Entity, CatChoice)? {
    if let model = await task(choice.model).value {
      return (model.clone(recursive: true), choice)
    }
    guard choice != .standard, let model = await task(CatChoice.standard.model).value else {
      return nil
    }
    return (model.clone(recursive: true), .standard)
  }

  private func task(_ model: CatModel) -> Task<Entity?, Never> {
    if let task = loading[model] { return task }
    let task = Task { await NookiAssets.compiledCat(model) }
    loading[model] = task
    return task
  }

}

/// The styled rooms of one scene, each kept once built, sharing meshes, materials and the cat.
@MainActor
final class GenzRoomCache {
  let kit = GenzKit()
  private(set) lazy var cats = GenzCatSource()
  private var rooms: [GenzLayout.Key: GenzRoom] = [:]
  /// The defaults suite each room keeps the places its furniture was moved to in; the app's own
  /// when nil.
  private let suite: String?

  nonisolated init(suite: String? = nil) {
    self.suite = suite
  }

  func room(_ layout: GenzLayout) -> GenzRoom {
    if let room = rooms[layout.key] { return room }
    let room = GenzRoom(
      layout: layout, kit: kit, cats: cats,
      spots: GenzSpotStore(
        defaults: suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard, key: layout.key))
    rooms[layout.key] = room
    return room
  }
}

/// One styled room and everything that moves in it. Built from simple shapes in code, so it is
/// ready a moment after it is asked for; only the cat loads from a file.
@MainActor
final class GenzRoom: CatPlayStage {
  static let catName = "genz-cat"
  static let noteName = "genz-note"
  static let lampName = "genz-lamp"
  static let lensName = "genz-lens"
  static let bulbName = "genz-bulb"
  /// The bulb seen under a shade, which keeps its own glow when the shade's changes.
  static let bulbGlassName = "genz-bulb-glass"
  static let posterName = "genz-poster"
  /// A candle's flame, which flickers.
  static let flameName = "genz-flame"
  static let lightDotName = "genz-light-dot"
  /// How high the decorate marker floats: over the tallest rug (the pattern rug's dots, 56 mm),
  /// so it never shares a plane with one or hides under it.
  static let markerHeight: Float = 0.08

  let layout: GenzLayout
  let root = Entity()
  let screen = GenzRoomScreen()
  var art: any RoomLayerArt = GenzNativeArt()
  private(set) var camera: GenzCamera
  private(set) var isBuilt = false
  private(set) var hasCat = false

  private let kit: GenzKit
  private let cats: GenzCatSource
  let room = Entity()
  private let lens = PerspectiveCamera()
  let catHolder = Entity()
  /// The cat moments switched on in Labs.
  private(set) var moments: Set<CatMoment> = []
  /// The purr and its hearts, for the view to draw.
  let purr = CatPurr()
  /// The hands on the cat: petting, play and the cooldowns that keep it from feeling spammy.
  let hands = CatHands()
  /// The toys on the cat's floor, and the game going on with one.
  let toys = RoomToys()
  /// Where the room reports what happens outside a touch, such as a game the cat won.
  var report: (@MainActor (PetSceneEvent) -> Void)?
  /// Where the body faces this frame, before the lean into a hand.
  var bodyHeading: Float = 0
  private var lastCatClock = 0.0
  var trip: CatTrip?
  var tripKind: CatTripKind?
  var playClock = CatPlayClock(seed: UInt64.random(in: 1...UInt64.max))
  private var lastBat = -Double.infinity
  private var greetPending = false
  /// Whether a measuring run has been told this room is drawing since it last came on screen.
  private var isAnnounced = false
  private var lastSeenSaved = -Double.infinity
  /// The scale the cat model is shown at, for matching its walk to how fast it moves.
  private var catScale: Float = 1
  /// A dot of lamp light on the cat's floor, for it to chase.
  let lightDot = ModelEntity()
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
  /// Candle flames, which flicker.
  private var flames: [ModelEntity] = []
  let lampLight = Entity()
  private let outsideLight = Entity()
  private let fillLight = Entity()
  private let headlight = Entity()
  var rig: CatRig?
  /// The cat's soft shadow, and the footprint it is easing towards, as fractions of its length.
  var catShadow: ModelEntity?
  var catShadowShape = GenzRoom.catShadowFootprint(.sleep)
  var behaviour = CatBehaviour(clips: [:])
  private var life = LifeDrive()
  private var lifeNeeds: PetNeeds?
  var lifeProps: GenzLifeProps?
  /// Where the cat was put down or called to, in place of its own spot, until it is sent back.
  var perch: (spot: SIMD2<Float>, heading: Float)?
  /// A cat just put down: the height it was let go from, and when.
  var dropped: (height: Float, clock: Double)?
  /// The lamp's extra warmth from Loved, in steps, so the light changes only now and then.
  private var lifeWarmth: Float = 0
  private var catChoice = CatChoice.standard
  private var catModel: Entity?
  private var catLoad: Task<Void, Never>?
  var gazePoint: SIMD3<Float>?
  var gazeUntil = 0.0
  private var building: Task<Void, Never>?
  private let frames = FrameClock()
  var viewSize = CGSize(width: 393, height: 852)
  var clock = 0.0
  private var openedClock: Double?
  private var noteClock = 0.0
  private var landedClock: Double?
  var petClock: Double?
  private var lampOn = true
  var reduceMotion = false
  var world = PetWorld()
  private var shownDrawing: CGImage?
  private var settlingFrames = 4
  private var isOnScreen = false
  private var viewsShowing = Set<UUID>()
  private var lastTexture = -1.0
  private var lastLevels: [String: Double] = [:]
  var tapTimer = NookiTapTimer()
  private var texturesBeingMade = Set<String>()
  private var pendingFlyIn: PetSceneFlyIn?
  var opening: SceneFlight?
  private var tiltSource: (any NookiTiltSource)?
  private var tilt = NookiTilt()
  private var ambientLight: Entity?
  private let dayLamp = Entity()
  /// The look the sunset disc's texture holds now.
  private var drawnDisc: DiscLook?
  private(set) var glow: GenzGlow?
  /// The lighting preset the room is lit with.
  private(set) var look = LightingLook.off
  /// Called when an opening asked for through ``flyIn(_:)`` is over.
  var onOpeningEnded: (() -> Void)?
  private var dayLight: PetSceneDayLight?
  private var viewRecipe: any ViewRecipe = ViewRecipes.recipe(for: .standard)
  /// The last thing outside the cat pawed at, so each drop is pawed at once.
  private var pawedAt: Int64?
  /// Whether the cat's gaze is on something outside rather than a finger.
  private var watchingView = false

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "GenzRoom")
  private static let orbitPerPoint: Float = 0.004
  /// The lens's clip planes. The camera never comes within a few units of the room, and stands
  /// at most about a hundred off in the opening at full zoom out, so a near plane this far out
  /// keeps the depth fine enough that the rug, poster and note never shimmer against what they
  /// rest on. The default near plane of a centimetre left too little depth twenty units out.
  static let nearClip: Float = 0.5
  static let farClip: Float = 300
  private static let discPixels = 512
  private static let posterPixels = 128
  private static let textureStep = 1.0 / 15
  /// The poster's sun turns slowly, so a few updates a second are enough.
  private static let posterStep = 0.25
  private static let petLength = 4.0
  private static let parallaxPoints: CGFloat = 60
  private static let ambientExponent: Float = 1.6

  /// The furniture on the floor, which can be picked up and moved while the room is decorated.
  let decor: DecorSession
  let spots: GenzSpotStore
  /// The bulb the lamp light shines from, which moves with the lamp's table.
  var lampBulb: Entity?

  init(layout: GenzLayout, kit: GenzKit, cats: GenzCatSource, spots: GenzSpotStore) {
    self.layout = layout
    self.kit = kit
    self.cats = cats
    self.spots = spots
    decor = DecorSession(
      plan: DecorPlan(minimum: .zero, maximum: layout.floor, grid: 0.25),
      liftHeight: 0.45, markerHeight: Self.markerHeight, markerMargin: 0.12)
    camera = GenzCamera(home: layout.camera)
    lens.camera.fieldOfViewInDegrees = layout.camera.fieldOfView
    lens.camera.near = Self.nearClip
    lens.camera.far = Self.farClip
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
    await kit.makeTextures()
    for part in layout.shell(kit) { room.addChild(part) }
    let holders = layout.pieces.map(place)
    arrangeDecor(holders)
    buildLED()
    buildDisc()
    buildNote()
    await Task.yield()
    addLighting()
    buildBackstop()
    buildLightDot()
    buildToys()
    buildCareProps()
    catHolder.name = Self.catName
    catHolder.position = layout.cat.spot.scene
    catHolder.orientation = simd_quatf(angle: layout.cat.heading, axis: [0, 1, 0])
    bodyHeading = layout.cat.heading
    let length = layout.cat.length
    NookiDiorama.makeTappable(
      catHolder, size: [length * 0.8, length * 0.6, length * 0.8], center: [0, length * 0.3, 0])
    room.addChild(catHolder)
    let props = GenzLifeProps(kit: kit, catLength: length)
    props.place(at: layout.cat.spot.scene, heading: layout.cat.heading)
    props.roomHasYarn = true
    props.show(lifeNeeds)
    room.addChild(props.root)
    lifeProps = props
    let glow = GenzGlow(layout: layout, kit: kit)
    catShadow = glow.shadeCat(in: catHolder, length: length)
    glow.follow(holders)
    room.addChild(glow.root)
    self.glow = glow
    applyLook()
    isBuilt = true
    NookiTrace.mark("styled room built")
    room.isEnabled = isOnScreen
    applyLevels()
    updateScreen()
    await placeCat()
  }

  /// The piece for `placement`, inside a holder standing at its spot and turned its way.
  static func placed(_ placement: GenzLayout.Placement, kit: GenzKit) -> (
    holder: Entity, piece: Entity
  ) {
    let piece = kit.build(placement.piece)
    kit.merge(piece, key: "\(placement.piece)")
    let size = placement.piece.kind.size
    piece.position = GenzRoomPoint(-size.x / 2, -size.y / 2, 0).scene
    let holder = Entity()
    holder.position = placement.centre.scene
    holder.orientation = simd_quatf(angle: placement.yaw, axis: [0, 1, 0])
    holder.addChild(piece)
    return (holder, piece)
  }

  private func place(_ placement: GenzLayout.Placement) -> Entity {
    let (holder, piece) = Self.placed(placement, kit: kit)
    let size = placement.piece.kind.size
    room.addChild(holder)
    switch placement.piece.kind {
    case .sunsetLamp, .thriftLamp, .pleatedLamp:
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
      case Self.bulbGlassName: break
      case Self.flameName: flames.append(model)
      default:
        let isShaded = [.thriftLamp, .pleatedLamp].contains(placement.piece.kind)
        if isShaded, model.model?.materials.first is UnlitMaterial {
          shades.append(model)
        }
      }
    }
    if let bulb = piece.findEntity(named: Self.bulbName) {
      lampLight.position = bulb.position(relativeTo: room)
      lampBulb = bulb
    }
    return holder
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
    let anatomy = shown.model.anatomy
    let scale = layout.cat.length / anatomy.length
    model.scale = .one * scale
    catScale = scale
    model.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
    let rig = CatRig(model: model, clips: CatCatalog.clips(shown.model), anatomy: anatomy)
    if let palette = CatCatalog.palette(shown.model, coat: shown.coat) { rig?.paint(palette) }
    let action = self.rig?.current ?? .sleep
    catModel?.removeFromParent()
    catModel = model
    self.rig = rig
    behaviour = CatBehaviour(clips: rig?.info ?? [:], seed: UInt64.random(in: 1...UInt64.max))
    behaviour.follow(life)
    rig?.play(rig?.info[action] != nil ? action : .sleep, blend: 0)
    catHolder.addChild(model)
    if let receiver = ambientReceiver { NookiDiorama.visit(model) { $0.components.set(receiver) } }
    hasCat = true
    NookiTrace.mark("styled cat placed")
  }

  // MARK: - Light

  private var ambientReceiver: ImageBasedLightReceiverComponent?

  private func addLighting() {
    let isSunset = layout.style == .sunsetLamp
    if let environment = Self.ambient(top: ambientColours.top, bottom: ambientColours.bottom) {
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
        color: outsideColour.platformColour, intensity: 0))
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
    if !isOnScreen, !viewsShowing.isEmpty { NookiTrace.mark("styled room shown") }
    isOnScreen = !viewsShowing.isEmpty
    if isOnScreen, !wasOnScreen {
      greetPending = CatGreeting.isDue(lastSeen: CatSeen.last, now: .now)
    }
    if !isOnScreen, wasOnScreen { CatSeen.mark() }
    if !isOnScreen { isAnnounced = false }
    room.isEnabled = isOnScreen && isBuilt
    frames.isPaused = !isOnScreen
    if isOnScreen { tiltSource?.start() } else { tiltSource?.stop() }
  }

  /// Starts stepping the room, after a few frames' settling, for a view that has just added it.
  func startUpdates() {
    settlingFrames = 4
    frames.isPaused = !isOnScreen
    frames.run { [weak self] delta in self?.tick(delta) }
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

  /// Tells a measuring run that this room is drawing, and how to drive it.
  private func announce() {
    isAnnounced = true
    ScenePerf.shown(
      ScenePerf.Scene(
        name: "\(layout.style.rawValue) room",
        orbit: { [weak self] in self?.orbit(byX: $0, y: $1) },
        zoom: { [weak self] in self?.zoom(by: $0) },
        release: { [weak self] in self?.endOrbit(velocityX: 0, velocityY: 0) },
        census: { [weak self] in self.map { SceneCensus.of($0.root) } ?? "" }))
  }

  private func aimLens() {
    lens.look(at: camera.target, from: camera.position, relativeTo: nil)
    updateScreen()
  }

  /// Projects what the flat layers follow, and where the cat is, into the view.
  func updateScreen() {
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
    var lights = GlowSpots()
    if look.isLit {
      let middle = GenzRoomPoint(layout.cat.spot.x, layout.cat.spot.y, 2)
      if let low = project(middle),
        let high = project(GenzRoomPoint(middle.x, middle.y, middle.z + 1))
      {
        lights.pointsPerUnit = hypot(high.x - low.x, high.y - low.y)
      }
      lights.bulbs = look.fairy.shown ? (glow?.bulbPoints ?? []).compactMap(project) : []
      lights.led = GlowSpots.along(layout.led, every: 0.7).compactMap(project)
      lights.lamp = project(layout.lamp.at)
      lights.pool = project(GenzGlow.pool(layout))
    }
    if screen.lights != lights { screen.lights = lights }
    if screen.window != window { screen.window = window }
    let home = camera.atHome
    let homeWindow = layout.window.compactMap { home.project($0.scene, in: viewSize) }
    if screen.homeWindow != homeWindow { screen.homeWindow = homeWindow }
    let cat = camera.project(catHolder.position + [0, layout.cat.length * 0.55, 0], in: viewSize)
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
      if settlingFrames == 0 {
        NookiTrace.mark("styled room on screen")
        if openedClock == nil { startOpening() }
      }
      return
    }
    if ScenePerf.isOn, !isAnnounced { announce() }
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
    stepView()
    stepFlames()
    stepDecor(Float(delta))
    applyCat()
    applyLevels()
  }

  /// Each flame sways and stretches a little, out of step with the others.
  private func stepFlames() {
    guard !reduceMotion else { return }
    for (index, flame) in flames.enumerated() {
      let phase = clock * 7 + Double(index) * 1.7
      let stretch = Float(1 + 0.1 * sin(phase) + 0.05 * sin(phase * 2.3))
      let sway = Float(0.06 * sin(phase * 0.8 + 0.5))
      flame.scale = [1 / stretch.squareRoot(), stretch, 1 / stretch.squareRoot()]
      flame.orientation = simd_quatf(angle: sway, axis: [0, 0, 1])
    }
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

  /// Lights the room with `lighting`: its fairy lights, sun, rim light and shadows, the lamp as
  /// key light, the ambient fill, and the colours of the LED and the light from outside.
  func setLighting(_ lighting: RoomLighting) {
    let look = LightingLook.of(lighting)
    guard look != self.look else { return }
    self.look = look
    applyLook()
  }

  /// How much brighter than its own the lamp shines now: the preset's boost, flickering when the
  /// preset says so.
  private var lampBoost: Float {
    let flicker = look.key.flicker
    guard flicker > 0, !reduceMotion else { return look.key.boost }
    let wave = sin(clock * 9.1) * 0.5 + sin(clock * 23.7 + 1.3) * 0.3 + sin(clock * 3.3) * 0.2
    return look.key.boost * (1 - flicker * Float(0.5 + 0.5 * wave))
  }

  private func applyLook() {
    glow?.apply(look)
    updateScreen()
    let lamp = GenzColour.mix(
      GenzColour.mix(layout.lampColour, look.key.colour.genz, by: look.key.warmth),
      Self.lovedLamp, by: lifeWarmth)
    let soft = look.key.softness
    switch layout.style {
    case .sunsetLamp:
      lampLight.components[SpotLightComponent.self]?.color = lamp.platformColour
      lampLight.components[SpotLightComponent.self]?.innerAngleInDegrees = 18 + 8 * soft
      lampLight.components[SpotLightComponent.self]?.outerAngleInDegrees = 46 + 14 * soft
    case .windowSeat:
      lampLight.components[PointLightComponent.self]?.color = lamp.platformColour
      lampLight.components[PointLightComponent.self]?.attenuationRadius = 6 + 3 * soft
    case .nooki: break
    }
    outsideLight.components[DirectionalLightComponent.self]?.color =
      (look.outside?.genz ?? outsideColour).platformColour
    applyFill()
    lastLevels["lamp"] = nil
    lastLevels["led"] = nil
  }

  /// The colour of the light from outside, before a preset changes it.
  private var outsideColour: GenzColour {
    layout.style == .sunsetLamp ? GenzColour(0x8FA6D8) : GenzColour(0xFFD9A0)
  }

  /// The room's own ambient light from above and below, before a preset changes it.
  private var ambientColours: (top: GenzColour, bottom: GenzColour) {
    layout.style == .sunsetLamp
      ? (GenzColour(0xE8D8E0), GenzColour(0xA08890)) : (GenzColour(0xC8D4E8), GenzColour(0x8090A8))
  }

  /// Tints the ambient light towards the preset's fill.
  private func applyFill() {
    guard var ambient = ambientLight?.components[ImageBasedLightComponent.self] else { return }
    let own = ambientColours
    let fill = look.fill
    let lit = look.isLit
    if let environment = Self.ambient(
      top: lit ? GenzColour.mix(own.top, fill.top.genz, by: 0.75) : own.top,
      bottom: lit ? GenzColour.mix(own.bottom, fill.bottom.genz, by: 0.75) : own.bottom)
    {
      ambient.source = .single(environment)
    }
    ambientLight?.components.set(ambient)
    applyDayLight()
  }

  /// Lights the room for the hour here. `nil` keeps the room's own night.
  func show(dayLight: PetSceneDayLight?) {
    guard dayLight != self.dayLight else { return }
    self.dayLight = dayLight
    if let here = dayLight?.here, here.lampOn != lampOn { toggleLamp() }
    applyDayLight()
    applyViewHour()
  }

  // MARK: - The view outside

  /// Shows `choice` through the window: its view, weather and hour.
  func setWindowView(_ choice: WindowViewChoice) {
    guard choice != screen.windowView else { return }
    screen.windowView = choice
    viewRecipe = ViewRecipes.recipe(for: choice.view)
    applyViewHour()
  }

  private func applyViewHour() {
    let hour = screen.windowView.shownHour(room: dayLight?.here)
    if screen.viewHour != hour { screen.viewHour = hour }
  }

  /// The cat follows what moves outside with its head, and paws at a drop running down the glass
  /// beside it when it is up. A finger on the screen comes first.
  private func stepView() {
    guard layout.style == .windowSeat, trip == nil, !reduceMotion else { return }
    let look = ViewLook(
      view: screen.windowView.view, hour: screen.viewHour, weather: screen.windowView.shownWeather)
    let moment = ViewMoment(
      look: look, now: Date().timeIntervalSinceReferenceDate, time: openingTime)
    guard moment.time > GenzOpening.length, let interest = ViewRecipes.interest(at: moment) else {
      watchingView = false
      return
    }
    let fingerHasGaze = gazePoint != nil && clock <= gazeUntil && !watchingView
    guard !fingerHasGaze else { return }
    headLook(at: outsidePoint(interest), for: 0.3)
    watchingView = true
    if interest.paw, interest.id != pawedAt, behaviour.isAwake(at: clock) {
      pawedAt = interest.id
      behaviour.react(.bat, at: clock)
    }
  }

  /// Where a thing outside is in the scene: on the window's plane, pushed out beyond the glass by
  /// how far back its plane is.
  private func outsidePoint(_ interest: ViewInterest) -> SIMD3<Float> {
    let xs = layout.window.map(\.x)
    let zs = layout.window.map(\.z)
    let (x0, x1) = (xs.min() ?? 0, xs.max() ?? 1)
    let (z0, z1) = (zs.min() ?? 0, zs.max() ?? 1)
    let glass = layout.window.first?.y ?? 0
    let depth: Float =
      switch interest.plane {
      case nil: 0.05
      case .near: 2
      case .street: 9
      case .middle: 18
      case .far: 40
      }
    let x = x0 + Float(interest.point.x / 100) * (x1 - x0)
    let z = z1 - Float(interest.point.y / ViewStage.windowHeight) * (z1 - z0)
    let point = GenzRoomPoint(x, glass - depth, z)
    return room.convert(position: point.scene, to: nil)
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
    dayLamp.isEnabled = look != nil
    guard var ambient = ambientLight?.components[ImageBasedLightComponent.self] else { return }
    ambient.intensityExponent =
      Self.ambientExponent + Self.ambientShift(look, phase: dayLight?.here.phase)
      + self.look.fill.shift
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
    var headingGoal = homeHeading
    stepToys()
    if let pose = stepHeld() {
      mode = .fixed(pose.action)
      headingGoal = pose.heading
    } else if let pose = stepPursuit() {
      mode = .fixed(pose.action)
      headingGoal = pose.heading
      if pose.action == .walk { rate = walkRate(pose.speed) }
    } else if let pose = stepTrip() {
      mode = .fixed(pose.action)
      headingGoal = pose.heading
      if pose.action == .walk { rate = walkRate(pose.speed) }
    }
    let step = Float(min(clock - lastCatClock, 0.1))
    bodyHeading = Self.turn(bodyHeading, towards: headingGoal, step: step)
    if toys.liftedAt == nil { settleDrop() }
    hands.stepLean(step, reduceMotion: reduceMotion)
    lastCatClock = clock
    catHolder.orientation =
      simd_quatf(angle: bodyHeading, axis: [0, 1, 0])
      * simd_quatf(angle: hands.lean, axis: [0, 0, 1])
    let beat = behaviour.beat(at: clock, mode: mode)
    rig.play(beat.action, rate: rate)
    fitCatShadow(step)
    if clock > gazeUntil { gazePoint = nil }
    rig.look(
      at: gazePoint ?? lens.position(relativeTo: nil),
      weight: Float(
        CatBehaviour.lookWeight(for: beat, holding: gazePoint != nil, reduceMotion: reduceMotion)))
  }

  /// How long the head stays on a finger after it last moved.
  private static let fingerLookLength = 1.5

  /// Turns the head and neck, not the body, towards `point` for `length` seconds.
  func headLook(at point: SIMD3<Float>, for length: Double) {
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
    watchingView = false
  }

  /// The cat as drawn now, for finding where a finger is on it.
  func catBody() -> CatBodyOnScreen? {
    CatBodyOnScreen.of(
      base: catHolder.position, heading: bodyHeading, length: layout.cat.length,
      isOnBack: hands.isOnBack(at: clock), anatomy: rig?.anatomy ?? .madeCat
    ) { camera.project($0, in: viewSize) }
  }

  /// Whether a finger at `point` is on the cat, for telling a stroke from a turn of the room.
  func isOverCat(_ point: CGPoint) -> Bool {
    if let body = catBody() { return body.contains(SIMD2(Double(point.x), Double(point.y))) }
    guard let cat = screen.cat else { return false }
    return hypot(point.x - cat.x, point.y - cat.y) < 70
  }

  /// A stroke starting at `point` on the cat. Reports a pet like a tap does.
  func stroke(at point: CGPoint) -> [PetSceneEvent] {
    let fresh = petClock == nil
    petClock = clock
    behaviour.react(.pet, at: clock)
    hands.beginStroke(at: point)
    let events = strokeMoved(to: point)
    return fresh ? [.petted] + events : events
  }

  /// The finger strokes on: the cat leans into it, purrs as the spot deserves, and rolls over
  /// after a long pet. A rub on its belly may get grabbed.
  func strokeMoved(to point: CGPoint) -> [PetSceneEvent] {
    guard trip == nil else { return [] }
    petClock = clock
    if moments.contains(.purrs), purr.touch(at: clock, cat: point) {
      behaviour.react(.roll, at: clock)
      hands.onBackUntil = clock + behaviour.length(of: behaviour.playable(.rollOver), held: 3)
    }
    guard let body = catBody(), let response = hands.stroke(to: point, on: body, at: clock)
    else { return [] }
    return show(response)
  }

  func strokeEnded() { hands.endStroke() }

  /// A treat or the partner's pet: the cat reacts without telling anyone.
  func react(_ reaction: CatReaction) {
    petClock = clock
    behaviour.react(reaction, at: clock)
  }

  /// The partner petted the cat on their phone: a heart over it, and it perks up.
  func partnerPetted() {
    react(.pet)
    if let response = hands.play.handle(.partnerPetted, at: clock) { _ = show(response) }
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
    let boost = lampBoost
    if changed("lamp", click + bloom * 10 + warmth * 100 + Double(boost) * 1_000, step: 0.02) {
      lampLight.setLight(intensity: Float(click) * 90_000 * Float(1 + 0.3 * warmth) * boost)
      fillLight.setLight(intensity: Float(bloom) * 26_000 * Float(1 + 0.4 * warmth))
    }
    // The lens follows the switch alone: a candle's flicker moves the light, not its material.
    if changed("lens", click, step: 0.02) {
      for lens in lenses {
        lens.model?.materials = [kit.glow(GenzColour(0xFFB066).shaded(Float(click) - 1))]
      }
    }
    let moon = GenzOpening.eased(time, from: 0.2, length: 1)
    if changed("moon", moon) {
      outsideLight.setLight(intensity: Float(moon) * 420)
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
      outsideLight.setLight(intensity: Float(street) * 900)
    }
    let led = GenzOpening.windowLED(time)
    if changed("led", led, step: 0.05) { setLED(led) }
    let lamp = (lampOn ? GenzOpening.eased(time, from: 1.4, length: 0.8) : 0)
    let boost = lampBoost
    if changed("lamp", lamp + warmth * 10 + Double(boost) * 100, step: 0.02) {
      lampLight.setLight(intensity: Float(lamp) * 9_000 * Float(1 + 0.3 * warmth) * boost)
    }
    // The shade follows the switch alone, as the sunset lamp's lens does.
    if changed("shade", lamp, step: 0.02) {
      for shade in shades {
        shade.model?.materials = [kit.glow(GenzColour(0xF3E3C3).shaded(Float(lamp) * 0.55 - 0.55))]
      }
    }
    let lit = GenzOpening.windowNote(clock - noteClock) * (0.85 + 0.15 * street)
    if changed("note", lit, step: 0.02) { setNote(opacity: 1, tint: 0.4 + 0.6 * lit) }
    let car =
      time > GenzOpening.length
      ? viewRecipe.headlight(at: Date().timeIntervalSinceReferenceDate) : nil
    let pass = car.map { $0.leftToRight ? $0.progress : 1 - $0.progress }
    if changed("headlight", pass ?? -1, step: 0.004) {
      let progress = Float(pass ?? 0)
      let x = -6 + 20 * progress
      headlight.look(
        at: GenzRoomPoint(x + 3, 4, 0.3).scene, from: GenzRoomPoint(x, -7, 2.2).scene,
        relativeTo: room)
      let fade = pass.map { sin(Float($0) * .pi) } ?? 0
      // Stays in the scene between cars: a light joining and leaving every pass costs a frame.
      headlight.components[SpotLightComponent.self]?.intensity = reduceMotion ? 0 : fade * 160_000
    }
  }

  private func setLED(_ level: Double) {
    let material = kit.glow((look.led?.genz ?? layout.ledColour).shaded(Float(level) * 0.9 - 0.9))
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
    // The native disc only changes with its bloom, the lamp and the warmth, so once it has
    // bloomed it is drawn again only when one of those changes.
    let disc = DiscLook(
      bloom: (GenzOpening.discBloom(time) * 100).rounded(), warmth: (warmth * 100).rounded(),
      lampOn: lampOn)
    let discIsDrawn = art is GenzNativeArt && discTexture != nil && disc == drawnDisc
    if discModel != nil, !discIsDrawn,
      let image = art.image(for: .sunsetDisc, state: state, pixels: Self.discPixels)
    {
      if discTexture != nil { drawnDisc = disc }
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

  /// What the native sunset disc was last drawn with.
  private struct DiscLook: Equatable {
    var bloom: Double
    var warmth: Double
    var lampOn: Bool
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
  /// Away from its place after a game, a call or being carried, on its way back.
  case wander
}

extension GenzRoom {
  /// Switches the cat moments to `moments`.
  func setMoments(_ moments: Set<CatMoment>) {
    self.moments = moments
    if !moments.contains(.greets) { greetPending = false }
  }

  /// A finger near the edge of the view catches the cat's eye: it looks, then bats at it, which
  /// counts as a game.
  func bat(at point: CGPoint) -> PetSceneEvent? {
    guard moments.contains(.batsAtFinger), trip == nil, toys.pursuit == nil,
      world.activity == .sleeping,
      clock - lastBat > Self.batGap,
      CatEdge.isNearEdge(x: Double(point.x), width: Double(viewSize.width))
    else { return nil }
    let played = clock - lastBat > Self.gameGap
    lastBat = clock
    followFinger(at: point)
    behaviour.react(.bat, at: clock)
    return played ? .played : nil
  }

  /// Bats closer together than this are one game.
  private static var gameGap: Double { 60 }

  /// Shows the needs in the room, or hides them for nil: the bowl, the yarn, the lamp's warmth.
  func showLife(_ needs: PetNeeds?) {
    lifeNeeds = needs
    lifeProps?.show(needs)
    let warmth = (GenzLifeProps.warmth(needs) * 20).rounded() / 20
    guard warmth != lifeWarmth else { return }
    lifeWarmth = warmth
    if isBuilt { applyLook() }
  }

  /// The amber the lamp leans toward as the cat feels loved.
  private static let lovedLamp = GenzColour(0xFFA860)

  /// Lets the cat's needs steer what it does on its own.
  func follow(_ life: LifeDrive?) {
    self.life = life ?? LifeDrive()
    behaviour.follow(self.life)
  }

  private static var batGap: Double { 2.5 }

  var home: SIMD2<Float> {
    if let perch { return perch.spot }
    let spot = layout.cat.spot.scene
    return SIMD2(spot.x, spot.z)
  }

  /// The way the cat faces at rest, at its own spot or where it was put.
  var homeHeading: Float { perch?.heading ?? layout.cat.heading }

  /// The cat's resting place as a point in the room.
  var homeScene: SIMD3<Float> { SIMD3(home.x, layout.cat.spot.scene.y, home.y) }

  /// How quickly the cat's body turns to a new heading: most of the way in a fifth of a second,
  /// so a lift, a drop or a call turns it rather than snapping it round.
  static let turnRate: Float = 14

  /// `heading` moved towards `goal` the short way round, for `step` seconds.
  static func turn(_ heading: Float, towards goal: Float, step: Float) -> Float {
    var difference = (goal - heading).truncatingRemainder(dividingBy: 2 * .pi)
    if difference > .pi { difference -= 2 * .pi }
    if difference < -.pi { difference += 2 * .pi }
    return heading + difference * (1 - exp(-turnRate * step))
  }

  /// How long a cat put down takes to come down onto the seat.
  static let dropLength: Float = 0.25

  /// Brings a cat just put down from where it hung to the seat, easing in as it lands.
  func settleDrop() {
    guard let dropped else { return }
    let into = Float(clock - dropped.clock) / Self.dropLength
    guard into < 1 else {
      self.dropped = nil
      catHolder.position.y = homeScene.y
      return
    }
    let fall = into * into
    catHolder.position.y = dropped.height + (homeScene.y - dropped.height) * fall
  }

  /// The cat's walking pace and running pace, in metres a second, from its size in this room.
  var walkSpeed: Float { layout.cat.length * 0.9 }
  var runSpeed: Float { layout.cat.length * 2.2 }

  /// A spot in front of the cat's place, for it to face when it is back.
  var homeFront: SIMD2<Float> {
    let heading = homeHeading
    return home + SIMD2(-sin(heading), -cos(heading)) * layout.cat.length
  }

  /// The patch the cat's shadow covers in each base pose, across and along its body, as fractions
  /// of its length: long and narrow standing, rounder sitting, a round patch curled up asleep.
  static func catShadowFootprint(_ base: CatBase) -> SIMD2<Float> {
    switch base {
    case .stand: [0.42, 0.92]
    case .sit: [0.5, 0.62]
    case .sleep: [0.64, 0.64]
    }
  }

  /// Keeps the cat's shadow flat on the seat under the cat, whatever the cat does above it: level
  /// when the cat leans, on the seat and smaller when the cat is lifted, and shaped like its pose.
  func fitCatShadow(_ step: Float) {
    guard let catShadow, let parent = catHolder.parent else { return }
    let base = rig?.current.flatMap { rig?.info[$0]?.base } ?? .sleep
    catShadowShape += (Self.catShadowFootprint(base) - catShadowShape) * min(step * 5, 1)
    let length = layout.cat.length
    let ground = layout.cat.spot.scene.y
    let height = max(catHolder.position.y - ground, 0)
    let shrink = 1 - 0.45 * min(height / length, 1)
    catShadow.setPosition(
      [catHolder.position.x, ground + Self.catShadowHeight, catHolder.position.z],
      relativeTo: parent)
    catShadow.setOrientation(simd_quatf(angle: bodyHeading, axis: [0, 1, 0]), relativeTo: parent)
    catShadow.scale = [catShadowShape.x * shrink, 1, catShadowShape.y * shrink]
  }

  static let catShadowHeight: Float = 0.015

  /// The walk clip's speed for moving at `speed`, at the cat's size here.
  func walkRate(_ speed: Float) -> Float {
    let natural = NookiClip.walkingSpeed * catScale / NookiDiorama.catScale
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
      trip == nil && toys.pursuit == nil && world.activity == .sleeping && !reduceMotion && hasCat
      && opening == nil
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
    let under = layout.onCatSurface(
      CatTrip.towards(
        target, from: home, upTo: layout.cat.length * 2.4, keep: layout.cat.length * 0.45))
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
    let near = layout.onCatSurface(CatTrip.towards(eye, from: home, upTo: layout.cat.length * 1.6))
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
      return layout.onCatSurface(
        home + SIMD2(-sin(heading), -cos(heading)) * layout.cat.length * reach)
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

  func begin(_ kind: CatTripKind, legs: [CatTrip.Leg]) {
    let heading = homeHeading
    trip = CatTrip(
      from: home, heading: heading, legs: legs.clear(of: layout, from: home), at: clock)
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
    case .greeting, .wander: break
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
    // Clear of the surface it lands on, so the two never fight for the same pixels.
    let height = layout.cat.spot.scene.y + 0.012
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

  func endTrip() {
    if tripKind == .delivery {
      note.position = layout.note.centre.scene
      note.scale = .one
    }
    lightDot.isEnabled = false
    trip = nil
    tripKind = nil
    catHolder.position = homeScene
    catHolder.orientation = simd_quatf(angle: homeHeading, axis: [0, 1, 0])
    updateScreen()
  }

  func buildLightDot() {
    let radius = layout.cat.length * 0.07
    lightDot.model = ModelComponent(
      mesh: LowPoly.cylinder(height: 0.002, radius: radius),
      materials: [UnlitMaterial(color: .init(red: 1, green: 0.42, blue: 0.3, alpha: 1))])
    lightDot.name = Self.lightDotName
    lightDot.isEnabled = false
    room.addChild(lightDot)
  }
}
