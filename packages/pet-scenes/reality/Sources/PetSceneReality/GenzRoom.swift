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

/// The cat model, loaded once from the room's own files and cloned into each styled room, so a
/// replaced `Cat` model shows up here without changes.
@MainActor
final class GenzCatSource {
  private var loading: Task<Entity?, Never>?
  private let load: NookiModelLoader

  init(load: NookiModelLoader? = nil) {
    let assets = NookiAssets()
    self.load = load ?? { name throws(NookiLoadError) in try await assets.model(name) }
  }

  func cat() async -> Entity? {
    if loading == nil {
      let load = load
      loading = Task { try? await load(NookiAssets.mochiName) }
    }
    return await loading?.value?.clone(recursive: true)
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
  private var animator: NookiCatAnimator?
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

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "GenzRoom")
  private static let orbitPerPoint: Float = 0.004
  private static let discPixels = 512
  private static let posterPixels = 128
  private static let textureStep = 1.0 / 15
  /// The poster's sun turns slowly, so a few updates a second are enough.
  private static let posterStep = 0.25
  private static let petLength = 4.0
  private static let parallaxPoints: CGFloat = 60

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

  private func placeCat() async {
    guard let model = await cats.cat() else {
      Self.log.error("No cat for \(self.layout.style.rawValue, privacy: .public)")
      return
    }
    let bounds = model.visualBounds(relativeTo: nil)
    let reach = max(bounds.extents.x, bounds.extents.z)
    guard !bounds.isEmpty, reach > 0, reach.isFinite else { return }
    let scale = layout.cat.length / reach
    model.scale = .one * scale
    model.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
    animator = NookiCatAnimator(model: model)
    animator?.play(.sleep, blend: 0)
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
        ImageBasedLightComponent(source: .single(environment), intensityExponent: 1.6))
      room.addChild(ambient)
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
    isOnScreen = !viewsShowing.isEmpty
    room.isEnabled = isOnScreen && isBuilt
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

  func petCat() -> PetSceneEvent {
    petClock = clock
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
    if !camera.isAtRest {
      camera.step(Float(delta))
      aimLens()
    }
    applyCat()
    applyLevels()
  }

  private var openingTime: Double { openedClock.map { clock - $0 } ?? 0 }

  private func applyCat() {
    guard let animator else { return }
    if let petClock, clock - petClock > Self.petLength { self.petClock = nil }
    let clip: NookiClip =
      switch world.activity {
      case .delivering: .idle
      case .settling: .sit
      case .sleeping: petClock == nil ? .sleep : .idle
      }
    animator.play(clip)
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
