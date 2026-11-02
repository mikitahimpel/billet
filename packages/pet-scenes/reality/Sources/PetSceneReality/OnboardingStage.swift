import CoreGraphics
import Foundation
import OSLog
import PetScene
import RealityKit

/// The first-launch scene: a deep windowsill at night with candles at both ends, fairy lights
/// along the top of the window, and a soft glossy heart floating over a cushion in the middle,
/// beating gently. The camera glides in out of the dark while the lights come on. Built from the
/// styled rooms' shared meshes and materials; only the heart loads from a file.
@MainActor
final class OnboardingStage: TabStage {
  static let heartName = "onboarding-heart"

  let root = Entity()
  let screen = TabScreen()
  var onEvent: ((OnboardingSceneEvent) -> Void)?

  private let kit: GenzKit
  private let room = Entity()
  private let view: TabCamera
  private let frames = FrameClock()
  private let lighting = TabLighting()
  private var look = LightingLook.off
  private var building: Task<Void, Never>?
  private var isBuilt = false
  private var isOnScreen = false
  private var reduceMotion = false
  private var receiver: ImageBasedLightReceiverComponent?

  /// Seconds since the scene began, which also runs the heart's beat and the flames.
  private var clock = 0.0
  /// Seconds into the flight: it runs faster once cut short, and stops at its end.
  private var flightTime = 0.0
  private var timeline = OnboardingTimeline(reduceMotion: false)
  private var moment = OnboardingSceneState.Moment.resting
  private var hasArrived = false
  private var squeezedAt: Double?

  /// Floats and sways; holds `beat`.
  private let heartFloat = Entity()
  /// Swells with the beat and squishes when tapped; holds the model.
  private let heartBeat = Entity()
  private var heartMaterial: PhysicallyBasedMaterial?
  private var flames: [Entity] = []

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "OnboardingStage")
  private static let flameColour = GenzColour(0xFFC46B)
  private static let beadColour = GenzColour(0xFFE2B0)
  private static let heartColour = GenzColour(0xFF6F7E)
  /// How much faster the rest of the flight runs once it is cut short.
  private static let hurry = 7.0

  init(kit: GenzKit) {
    self.kit = kit
    view = TabCamera(home: OnboardingLayout.camera)
    root.addChild(room)
    root.addChild(view.lens)
    room.isEnabled = false
  }

  // MARK: - Showing

  /// Starts over at `state`: flying in when it is arriving, at rest otherwise.
  func begin(_ state: OnboardingSceneState) {
    moment = state.moment
    hasArrived = false
    squeezedAt = nil
    switch state.moment {
    case .arriving: flightTime = 0
    case .resting: flightTime = timeline.duration
    }
    if isBuilt { apply(flightTime) }
  }

  /// Follows a change of `state`: resting cuts a flight short.
  func show(_ state: OnboardingSceneState) {
    guard state.moment != moment else { return }
    moment = state.moment
    if isBuilt { apply(flightTime) }
  }

  func start() {
    if building == nil { building = Task { await build() } }
    frames.isPaused = !isOnScreen
    frames.run { [weak self] delta in self?.tick(delta) }
  }

  func setOnScreen(_ onScreen: Bool) {
    isOnScreen = onScreen
    room.isEnabled = onScreen && isBuilt
    frames.isPaused = !onScreen
  }

  func setReduceMotion(_ reduced: Bool) {
    reduceMotion = reduced
    lighting.setReduceMotion(reduced)
    let done = flightTime >= timeline.duration
    timeline = OnboardingTimeline(reduceMotion: reduced)
    if done { flightTime = timeline.duration }
  }

  func setLighting(_ look: LightingLook) {
    guard look != self.look else { return }
    self.look = look
    guard isBuilt else { return }
    lighting.apply(look)
  }

  func fit(to size: CGSize) {
    view.fit(to: size)
  }

  /// The scene is framed for one view and holds still under a finger.
  func orbit(byX deltaX: Float, y deltaY: Float) {}

  func endOrbit(velocityX: Float, velocityY: Float) {}

  func tap(_ entity: Entity) {
    guard TabLook.named(Self.heartName, from: entity) != nil, hasArrived else { return }
    if !reduceMotion { squeezedAt = clock }
    onEvent?(.heartTapped)
  }

  // MARK: - Stepping

  private func tick(_ delta: TimeInterval) {
    clock += delta
    lighting.step(delta)
    guard isBuilt else { return }
    if flightTime < timeline.duration {
      let rate = moment == .resting ? Self.hurry : 1
      flightTime = min(flightTime + delta * rate, timeline.duration)
    }
    apply(flightTime)
    if !hasArrived, flightTime >= timeline.duration {
      hasArrived = true
      onEvent?(.arrived)
    }
  }

  /// Sets everything that follows the flight and the clock.
  private func apply(_ time: Double) {
    let away = timeline.away(time)
    let drift = reduceMotion ? 0 : Float(sin(clock * 0.16)) * 0.035
    view.fly(yaw: -0.6 * away + drift, pitch: 0.34 * away, distance: 1 + 2.4 * away)
    screen.darkness = timeline.darkness(time)
    lighting.setDimmer(timeline.warmth(time))
    stepHeart(time)
    stepFlames(time)
    updateGlows(time)
  }

  private func stepHeart(_ time: Double) {
    let glow = timeline.heartGlow(time)
    if reduceMotion {
      heartFloat.position = OnboardingLayout.heart.scene
      heartFloat.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
      heartBeat.scale = .one
    } else {
      let sway = HeartMotion.sway(clock)
      heartFloat.position = OnboardingLayout.heart.scene + [0, HeartMotion.bob(clock), 0]
      heartFloat.orientation =
        simd_quatf(angle: sway.yaw, axis: [0, 1, 0])
        * simd_quatf(angle: sway.roll, axis: [0, 0, 1])
      let squish = squeezedAt.map { HeartMotion.squish(clock - $0) } ?? .one
      heartBeat.scale = HeartMotion.scale(swell: HeartMotion.beat(clock) * glow) * squish
    }
    if var material = heartMaterial {
      let beat = reduceMotion ? 0 : HeartMotion.beat(clock)
      material.emissiveIntensity = (0.12 + 0.3 * glow) * (1 + 0.25 * beat)
      heartMaterial = material
      setHeartMaterial(material)
    }
  }

  private func stepFlames(_ time: Double) {
    for (index, flame) in flames.enumerated() {
      let lit = timeline.candle(index, time)
      let flicker = reduceMotion ? 1 : Float(GlowLights.flicker(0.12, time: clock + Double(index)))
      flame.isEnabled = lit > 0.01
      flame.scale = [lit, lit * (0.92 + 0.12 * flicker), lit]
    }
  }

  private func updateGlows(_ time: Double) {
    var glows: [TabGlow] = []
    let halos = lighting.haloScale
    let beat = reduceMotion ? 0 : Double(HeartMotion.beat(clock))
    for (index, candle) in OnboardingLayout.candles.enumerated() {
      let lit = Double(timeline.candle(index, time))
      guard lit > 0.01 else { continue }
      let flame = GenzRoomPoint(candle.spot.x, candle.spot.y, candle.spot.z + candle.height + 0.2)
      let flicker = reduceMotion ? 1 : GlowLights.flicker(0.15, time: clock + Double(index) * 1.7)
      guard let centre = view.project(flame.scene) else { continue }
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(2.2, at: flame.scene),
          colour: lighting.tint(Self.flameColour), strength: 0.55 * halos * lit * flicker))
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(0.5, at: flame.scene), colour: GenzColour(0xFFF1D6),
          strength: 0.7 * lit * flicker))
    }
    for (index, bead) in OnboardingLayout.beads.enumerated() {
      let lit = Double(timeline.bead(index, of: OnboardingLayout.beads.count, time))
      guard lit > 0.01, let centre = view.project(bead.scene) else { continue }
      let twinkle = reduceMotion ? 1 : 0.82 + 0.18 * sin(clock * 1.7 + Double(index) * 2.3)
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(0.5, at: bead.scene),
          colour: lighting.fairyColour ?? Self.beadColour, strength: 0.55 * halos * lit * twinkle))
    }
    let heart = Double(timeline.heartGlow(time))
    let point = heartFloat.position(relativeTo: nil)
    if heart > 0.01, let centre = view.project(point) {
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(OnboardingLayout.heartHeight * 2.1, at: point),
          colour: Self.heartColour, strength: (0.28 + 0.1 * beat) * heart * halos))
    }
    screen.glows = glows
  }

  // MARK: - Building

  private func build() async {
    buildShell()
    buildWindow()
    buildSill()
    buildCandles()
    buildBeads()
    await Task.yield()
    receiver = lighting.ambient(
      room, top: GenzColour(0xE8C4B0), bottom: GenzColour(0x5E3A3A), exponent: 1.2)
    addLights()
    rigLights()
    heartFloat.addChild(heartBeat)
    heartFloat.position = OnboardingLayout.heart.scene
    room.addChild(heartFloat)
    await loadHeart()
    lighting.apply(look)
    isBuilt = true
    room.isEnabled = isOnScreen
    screen.isLit = true
    apply(flightTime)
  }

  private func buildShell() {
    let (width, height, wall) = (
      OnboardingLayout.width, OnboardingLayout.height, OnboardingLayout.wall
    )
    let window = OnboardingLayout.window
    let plaster = kit.matte(GenzColour(0x6E4442))
    // The back wall, around the window's opening.
    room.addChild(kit.block(-wall, -wall, 0, width + wall * 2, wall, window.z0, plaster))
    room.addChild(
      kit.block(-wall, -wall, window.z1, width + wall * 2, wall, height - window.z1, plaster))
    room.addChild(
      kit.block(-wall, -wall, window.z0, window.x0 + wall, wall, window.z1 - window.z0, plaster))
    room.addChild(
      kit.block(
        window.x1, -wall, window.z0, width + wall - window.x1, wall, window.z1 - window.z0, plaster)
    )
    room.addChild(
      kit.block(-wall, -wall, -wall, width + wall * 2, 5, wall, kit.matte(GenzColour(0x3A2422))))
  }

  private func buildWindow() {
    let window = OnboardingLayout.window
    let night = GenzColour(0x1C2342)
    // The night beyond the glass, a little behind the wall.
    room.addChild(
      kit.block(
        window.x0, -0.5, window.z0, window.x1 - window.x0, 0.05, window.z1 - window.z0,
        kit.glow(night)))
    for star in OnboardingLayout.stars {
      room.addChild(
        kit.part(
          kit.box([star.size, star.size, 0.01]), kit.glow(GenzColour(0xFFF4DA)),
          at: GenzRoomPoint(star.x, -0.42, star.z).scene))
    }
    let moon = OnboardingLayout.moon
    room.addChild(
      kit.part(
        kit.prism(sides: 16, radius: moon.radius, top: moon.radius, height: 0.02),
        kit.glow(GenzColour(0xFFEFC8)), at: GenzRoomPoint(moon.x, -0.42, moon.z).scene,
        turn: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
    // The frame and the cross of its bars.
    let frame = kit.matte(GenzColour(0xF0DCC0))
    let bar: Float = 0.2
    room.addChild(
      kit.block(window.x0 - bar, -0.1, window.z1, window.x1 - window.x0 + bar * 2, 0.3, bar, frame))
    room.addChild(
      kit.block(
        window.x0 - bar, -0.1, window.z0 - bar, window.x1 - window.x0 + bar * 2, 0.3, bar, frame))
    room.addChild(
      kit.block(window.x0 - bar, -0.1, window.z0, bar, 0.3, window.z1 - window.z0, frame))
    room.addChild(kit.block(window.x1, -0.1, window.z0, bar, 0.3, window.z1 - window.z0, frame))
    let middle = (window.x0 + window.x1) / 2
    room.addChild(
      kit.block(middle - 0.06, -0.3, window.z0, 0.12, 0.1, window.z1 - window.z0, frame))
    room.addChild(
      kit.block(
        window.x0, -0.3, (window.z0 + window.z1) / 2 - 0.06, window.x1 - window.x0, 0.1, 0.12,
        frame))
  }

  private func buildSill() {
    let sill = OnboardingLayout.sill
    let top = OnboardingLayout.sillTop
    let wood = kit.matte(GenzColour(0x9A6644))
    room.addChild(
      kit.block(sill.x0, sill.y0, top - 0.28, sill.x1 - sill.x0, sill.y1 - sill.y0, 0.28, wood))
    room.addChild(
      kit.block(
        sill.x0 + 0.15, sill.y0, 0, sill.x1 - sill.x0 - 0.3, sill.y1 - sill.y0 - 0.25, top - 0.28,
        kit.matte(GenzColour(0x7E4E36))))
    // A runner of soft cloth under the cushion.
    room.addChild(kit.block(1.75, 0.35, top, 2.5, 2.1, 0.03, kit.matte(GenzColour(0xC97E78))))
    // The cushion the heart floats over.
    let cushion = OnboardingLayout.cushion
    room.addChild(
      kit.part(
        kit.prism(sides: 18, radius: 0.85, top: 0.7, height: 0.26),
        kit.matte(GenzColour(0xE6A2A0)), at: cushion.scene + [0, 0.03, 0]))
    room.addChild(
      kit.part(
        kit.prism(sides: 18, radius: 0.7, top: 0.55, height: 0.08),
        kit.matte(GenzColour(0xF1BDB6)), at: cushion.scene + [0, 0.29, 0]))
    // A small stack of books at the back, and a sprig in a glass jar.
    let books = kit.build(GenzPiece(.bookStack))
    let size = GenzPiece.Kind.bookStack.size
    let stack = Entity()
    stack.position = GenzRoomPoint(5.0, 2.2, top).scene
    stack.orientation = simd_quatf(angle: -0.4, axis: [0, 1, 0])
    stack.scale = .one * 1.3
    books.position = GenzRoomPoint(-size.x / 2, -size.y / 2, 0).scene
    stack.addChild(books)
    room.addChild(stack)
    let jar = GenzRoomPoint(0.75, 0.55, top).scene
    room.addChild(
      kit.part(
        kit.prism(sides: 10, radius: 0.22, top: 0.2, height: 0.5),
        kit.glow(GenzColour(0xB9D4CC), opacity: 0.45), at: jar))
    for index in 0..<3 {
      let lean = Float(index - 1) * 0.28
      room.addChild(
        kit.part(
          kit.box([0.04, 0.95, 0.04]), kit.matte(GenzColour(0x6F8F5E)),
          at: jar + [Float(index - 1) * 0.07, 0.75, 0],
          turn: simd_quatf(angle: lean, axis: [0, 0, 1])))
      room.addChild(
        kit.part(
          kit.prism(sides: 6, radius: 0.09, top: 0.04, height: 0.12),
          kit.matte(GenzColour(index == 1 ? 0xF4C6C0 : 0xFFE3B0)),
          at: jar + [Float(index - 1) * 0.07 - sin(lean) * 0.45, 1.18, 0]))
    }
  }

  private func buildCandles() {
    let wax = kit.matte(GenzColour(0xF6E7D2))
    let wick = kit.matte(GenzColour(0x3A2A24))
    for candle in OnboardingLayout.candles {
      let base = candle.spot.scene
      room.addChild(
        kit.part(
          kit.prism(
            sides: 12, radius: candle.radius, top: candle.radius * 0.97, height: candle.height),
          wax, at: base))
      // A little melted pool at the top.
      room.addChild(
        kit.part(
          kit.prism(sides: 12, radius: candle.radius * 0.8, top: candle.radius * 0.8, height: 0.01),
          kit.matte(GenzColour(0xFFF4E2)), at: base + [0, candle.height, 0]))
      room.addChild(
        kit.part(kit.box([0.03, 0.12, 0.03]), wick, at: base + [0, candle.height + 0.06, 0]))
      let flame = Entity()
      flame.position = base + [0, candle.height + 0.08, 0]
      flame.addChild(
        kit.part(
          kit.prism(sides: 8, radius: 0.09, top: 0.0, height: 0.36),
          kit.glow(Self.flameColour)))
      flame.addChild(
        kit.part(
          kit.prism(sides: 8, radius: 0.05, top: 0.0, height: 0.2),
          kit.glow(GenzColour(0xFFF6E0)), at: [0, 0.02, 0.02]))
      flame.isEnabled = false
      room.addChild(flame)
      flames.append(flame)
    }
  }

  private func buildBeads() {
    let materials = [kit.glow(Self.beadColour), kit.glow(GenzColour(0xFFC9A0))]
    let beads = OnboardingLayout.beads
    for (index, bead) in beads.enumerated() {
      room.addChild(
        kit.part(
          kit.prism(sides: 6, radius: 0.07, top: 0.05, height: 0.13), materials[index % 2],
          at: bead.scene))
    }
    // The wire between them.
    let wire = kit.matte(GenzColour(0x2E2420))
    for (from, to) in zip(beads, beads.dropFirst()) {
      let a = from.scene
      let b = to.scene
      room.addChild(
        kit.part(
          kit.box([0.02, 0.02, simd_distance(a, b)]), wire, at: (a + b) / 2,
          turn: simd_quatf(from: [0, 0, 1], to: simd_normalize(b - a))))
    }
  }

  private func addLights() {
    for candle in OnboardingLayout.candles {
      room.addChild(
        lighting.key(
          Self.flameColour, intensity: 5_500, reach: 4.5,
          at: GenzRoomPoint(candle.spot.x, candle.spot.y + 0.2, candle.spot.z + candle.height + 0.4)
        ))
    }
    let heart = OnboardingLayout.heart
    room.addChild(
      lighting.key(
        GenzColour(0xFF8E8A), intensity: 7_000, reach: 4,
        at: GenzRoomPoint(heart.x, heart.y + 1.6, heart.z - 0.6)))
    room.addChild(
      lighting.key(
        Self.beadColour, intensity: 4_000, reach: 5, at: GenzRoomPoint(3, 1.0, 8.4)))
  }

  /// The preset's rig: a rim behind the heart, a core light over the sill, and soft shadows under
  /// the candles and the cushion.
  private func rigLights() {
    let heart = OnboardingLayout.heart
    lighting.rim(
      at: heart.scene, from: GenzRoomPoint(heart.x + 0.6, heart.y - 2.4, heart.z + 2.6).scene)
    lighting.core(at: GenzRoomPoint(3, 2.6, 4.6).scene)
    lighting.sun(at: heart.scene, from: GenzRoomPoint(10, 6, 9).scene)
    for candle in OnboardingLayout.candles {
      let spot = candle.spot
      lighting.shadow(
        width: candle.radius * 3.2, depth: candle.radius * 3,
        at: GenzRoomPoint(spot.x, spot.y, spot.z + 0.012).scene)
    }
    let cushion = OnboardingLayout.cushion
    lighting.shadow(
      width: 2.4, depth: 2.1, at: GenzRoomPoint(cushion.x, cushion.y, cushion.z + 0.012).scene)
    room.addChild(lighting.root)
  }

  // MARK: - Heart

  private func loadHeart() async {
    let model = await Self.heartModel() ?? Self.fallbackHeart()
    let bounds = model.visualBounds(relativeTo: nil)
    guard !bounds.isEmpty, bounds.extents.y > 0 else {
      Self.log.error("The heart has no size")
      return
    }
    let scale = OnboardingLayout.heartHeight / bounds.extents.y
    model.scale = .one * scale
    model.position = -bounds.center * scale
    var material = PhysicallyBasedMaterial()
    material.baseColor = .init(tint: GenzColour(0xE8475E).platformColour)
    material.roughness = 0.32
    material.metallic = 0.0
    material.clearcoat = .init(floatLiteral: 1)
    material.clearcoatRoughness = .init(floatLiteral: 0.1)
    material.sheen = .init(tint: GenzColour(0xFFB49C).platformColour)
    material.emissiveColor = .init(color: GenzColour(0xFF4050).platformColour)
    material.emissiveIntensity = 0.12
    heartMaterial = material
    heartBeat.addChild(model)
    setHeartMaterial(material)
    if let receiver { NookiDiorama.visit(model) { $0.components.set(receiver) } }
    heartFloat.name = Self.heartName
    let reach = OnboardingLayout.heartHeight
    NookiDiorama.makeTappable(heartFloat, size: [reach * 1.4, reach * 1.2, reach], center: .zero)
  }

  private func setHeartMaterial(_ material: PhysicallyBasedMaterial) {
    NookiDiorama.visit(heartBeat) { entity in
      guard let model = entity as? ModelEntity, let count = model.model?.materials.count,
        count > 0
      else { return }
      model.model?.materials = Array(repeating: material, count: count)
    }
  }

  static func heartModel() async -> Entity? {
    guard let url = Bundle.module.url(forResource: "Heart", withExtension: "reality") else {
      log.error("Heart.reality is missing")
      return nil
    }
    do {
      return try await Entity(contentsOf: url)
    } catch {
      log.error("Heart.reality did not load: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /// Two soft balls side by side, so the scene still has its heart if the file will not load.
  private static func fallbackHeart() -> Entity {
    let heart = Entity()
    let mesh = MeshResource.generateSphere(radius: 0.5)
    for side: Float in [-1, 1] {
      let half = ModelEntity(mesh: mesh, materials: [SimpleMaterial()])
      half.position = [side * 0.32, 0.1, 0]
      half.scale = [0.85, 1, 0.8]
      heart.addChild(half)
    }
    return heart
  }
}
