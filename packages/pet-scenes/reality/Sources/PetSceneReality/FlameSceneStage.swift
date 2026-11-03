import CoreGraphics
import Foundation
import Observation
import Pet
import PetScene
import RealityKit

/// What the flat layers over the flame need, in the view's points.
@MainActor
@Observable
final class FlameScreen {
  var glows: [TabGlow] = []
  /// The window's opening as the camera sees it now, and from its home place.
  var window: [CGPoint] = []
  var homeWindow: [CGPoint] = []
  /// True once the scene is built and lit, so the glow can come up with it.
  var isLit = false
}

/// The pair's streak as a flame on the first-launch windowsill at night, the room's own view
/// through the window behind it. Two tongues twist round each other, one tinted for each partner;
/// the flame's size, colour, sparks, halo and the one light it casts all follow the streak's
/// growth. With no streak it rests as a glowing ember and never goes out.
///
/// Cheap by design: unlit meshes for the flame, a small pool of spark cubes stepped on the CPU,
/// a single point light, and the bloom drawn flat over the view. It steps only while on screen.
@MainActor
final class FlameSceneStage {
  static let flameName = "streak-flame"

  let root = Entity()
  let screen = FlameScreen()
  var onEvent: ((FlameSceneEvent) -> Void)?

  private let kit: GenzKit
  private let room = Entity()
  private let view: TabCamera
  private let frames = FrameClock()
  private var building: Task<Void, Never>?
  private var isBuilt = false
  private var isOnScreen = false
  private var reduceMotion = false
  private var receiver: ImageBasedLightReceiverComponent?

  private var state = FlameSceneState(flame: StreakFlame(streak: 0))
  private var look = FlameLook(flame: StreakFlame(streak: 0))
  /// Seconds since the scene was last opened, which runs the settle, the flicker and the moments.
  private var clock = 0.0
  private var frameCount = 0
  /// When the once-only moments of this visit began, on `clock`.
  private var burstAt: Double?
  private var rekindleAt: Double?
  private var pulseAt: Double?
  /// The moments wait for the scene to be built and on screen, so none plays unseen.
  private var pendingVisit: FlameVisit?

  /// The finger, as an offset from the flame's middle in room units, while one is down near it.
  private var finger: SIMD2<Float>?
  /// How far the flame leans towards the finger now, -1 (left) to 1 (right), and stretches up.
  private var lean = SIMD2<Float>.zero

  private let flame = Entity()
  private let mineTongue = Entity()
  private let theirsTongue = Entity()
  private let coreTongue = Entity()
  private let coal = Entity()
  private let light = Entity()
  private var pool: ModelEntity?
  private var holders: [FlameHolderKind: Entity] = [:]
  private var logs: [Entity] = []
  private var sparks: [Spark] = []
  private var sparkModels: [ModelEntity] = []
  private var spawnDebt: Float = 0
  /// The colours last given to the tongues, so materials are only rebuilt when they change.
  private var paintedLook: FlameLook?

  private static let sparkPool = FlameLook.mostSparks + FlameMoments.celebrationSparks
  /// The resting ember, which a rekindled flame grows out of.
  private static let ember = FlameLook(flame: StreakFlame(streak: 0))
  /// The pool of light's opacity as last written, so the material is only rebuilt on a change.
  private var poolOpacity: Float = -1
  private static let sparkLife: ClosedRange<Float> = 1.2...2.0
  /// The settle-in after opening: the camera eases a little closer.
  private static let settleLength = 2.4

  init(kit: GenzKit) {
    self.kit = kit
    view = TabCamera(home: FlameLayout.camera)
    root.addChild(room)
    root.addChild(view.lens)
    room.isEnabled = false
  }

  // MARK: - Showing

  /// Opens the scene at `state`, playing its visit's moments once it is on screen.
  func begin(_ state: FlameSceneState) {
    self.state = state
    look = FlameLook(flame: state.flame, today: state.today, reduceMotion: reduceMotion)
    clock = 0
    burstAt = nil
    rekindleAt = nil
    pulseAt = nil
    finger = nil
    lean = .zero
    sparks.removeAll(keepingCapacity: true)
    pendingVisit = state.visit
    if isBuilt { refresh() }
  }

  /// Follows a change of `state` while open, such as a note arriving.
  func show(_ state: FlameSceneState) {
    guard state != self.state else { return }
    let before = self.state
    self.state = state
    look = FlameLook(flame: state.flame, today: state.today, reduceMotion: reduceMotion)
    if state.visit != before.visit { pendingVisit = state.visit }
    if isBuilt { refresh() }
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
    guard reduced != reduceMotion else { return }
    reduceMotion = reduced
    look = FlameLook(flame: state.flame, today: state.today, reduceMotion: reduced)
    if isBuilt { refresh() }
  }

  func fit(to size: CGSize) {
    view.fit(to: size)
    projectWindow()
  }

  /// A finger at `point` in the view, or lifted when `nil`. The flame leans towards a finger near
  /// it and its sparks drift that way. True when the finger is on or close to the flame.
  @discardableResult
  func touch(at point: CGPoint?) -> Bool {
    guard let point, let centre = view.project(middle) else {
      finger = nil
      return false
    }
    let perPoint = 1 / max(Float(view.reach(1, at: middle)), 0.01)
    let offset = SIMD2(Float(point.x - centre.x), Float(centre.y - point.y)) * perPoint
    let near = simd_length(offset) < max(look.height * 1.6, 2.2)
    finger = simd_length(offset) < 5 ? offset : nil
    return near
  }

  /// The middle of the flame, in the scene.
  private var middle: SIMD3<Float> {
    let foot = FlameLayout.holder
    return GenzRoomPoint(foot.x, foot.y, foot.z + look.holder.flameFoot + look.height * 0.45).scene
  }

  // MARK: - Stepping

  private func tick(_ delta: TimeInterval) {
    clock += delta
    frameCount += 1
    guard isBuilt else { return }
    if let visit = pendingVisit {
      pendingVisit = nil
      play(visit)
    }
    settleCamera()
    let target = finger.map { SIMD2(min(max($0.x / 2.5, -1), 1), min(max($0.y / 4, -0.3), 1)) }
    let ease = Float(1 - exp(-(reduceMotion ? 4 : 7) * delta))
    lean += ((target ?? .zero) - lean) * ease
    stepFlame()
    stepSparks(Float(delta))
    // The flat glow follows at half the frame rate: the eye cannot tell, and it halves the redraws.
    if frameCount % 2 == 0 { updateGlows() }
  }

  private func play(_ visit: FlameVisit) {
    if visit.rekindled {
      rekindleAt = clock
      burstAt = clock + 0.9
      if !reduceMotion { throwSparks(FlameMoments.rekindleSparks, delay: 0.9) }
      onEvent?(.celebrated)
    } else if visit.milestone != nil {
      burstAt = clock + 0.5
      if !reduceMotion { throwSparks(FlameMoments.celebrationSparks, delay: 0.5) }
      onEvent?(.celebrated)
    }
    if visit.pulse { pulseAt = clock + (visit.rekindled || visit.milestone != nil ? 2.4 : 0.4) }
  }

  private func settleCamera() {
    guard !reduceMotion else {
      view.fly(yaw: 0, pitch: 0, distance: 1)
      return
    }
    let away = 1 - Float(OnboardingTimeline.smoother(clock / Self.settleLength))
    let drift = Float(sin(clock * 0.14)) * 0.025
    view.fly(yaw: drift, pitch: 0.04 * away, distance: 1 + 0.14 * away)
    if view.step(1 / 60) || frameCount % 30 == 0 { projectWindow() }
  }

  /// How strongly each moment shows now, 0 when it is not playing.
  private var swell: Float {
    burstAt.map { Float(FlameMoments.swell(clock - $0)) } ?? 0
  }

  private var pulse: Float {
    pulseAt.map { Float(FlameMoments.pulse(clock - $0)) } ?? 0
  }

  /// How far a rekindled flame has caught: 1 when it is not rekindling.
  private var caught: Float {
    rekindleAt.map { Float(FlameMoments.caught(clock - $0)) } ?? 1
  }

  private var flicker: Float {
    let amount = look.flicker * (reduceMotion ? 0.5 : 1)
    let time = reduceMotion ? clock * 0.4 : clock
    return Float(GlowLights.flicker(amount, time: time))
  }

  private func stepFlame() {
    let ember = Self.ember
    let caught = self.caught
    let height = mix(ember.height, look.height, caught) * (1 + 0.28 * swell + 0.12 * pulse)
    let width = mix(ember.width, look.width, caught) * (1 + 0.18 * swell + 0.06 * pulse)
    let flicker = self.flicker
    let breath = look.isEmber ? 0.88 + 0.12 * Float(sin(clock * (reduceMotion ? 0.6 : 1.1))) : 1
    let stretch = 1 + 0.14 * max(lean.y, 0)
    let leanAngle = -lean.x * 0.42
    let sway = reduceMotion ? 0 : Float(sin(clock * 1.3)) * 0.04
    let twist = Float(clock) * (reduceMotion ? 0.25 : 0.8)
    let tilt = simd_quatf(angle: leanAngle + sway, axis: [0, 0, 1])

    flame.position =
      GenzRoomPoint(
        FlameLayout.holder.x, FlameLayout.holder.y,
        FlameLayout.holder.z + look.holder.flameFoot
      ).scene
    let shown = look.isEmber && caught >= 1 ? breath : 1
    for (tongue, phase) in [(mineTongue, Float(0)), (theirsTongue, Float.pi)] {
      let angle = twist + phase
      let radius = width * 0.2
      let offset = SIMD3(cos(angle) * radius, 0, sin(angle) * radius)
      // Each tongue's tip leans across the middle, so the two cross as they twist.
      let across = simd_quatf(angle: 0.2, axis: simd_normalize(SIMD3(sin(angle), 0, -cos(angle))))
      tongue.position = offset
      tongue.orientation = tilt * across
      let own = 0.92 + 0.08 * Float(sin(clock * 2.1 + Double(phase)))
      tongue.scale = [width * 0.8, height * flicker * own * stretch * shown, width * 0.8]
    }
    coreTongue.orientation = tilt
    coreTongue.scale = [width * 0.42, height * 0.55 * flicker * stretch * shown, width * 0.42]
    let coalShown = look.isEmber || caught < 1
    coal.isEnabled = coalShown && look.holder == .dish
    coal.scale = .one * (coalShown ? breath : 1)

    let lit = look.isEmber ? breath : flicker
    let boost = 1 + 0.7 * swell + 0.35 * pulse
    let intensity = mix(ember.light, look.light, caught) * lit * boost
    light.setLight(intensity: intensity)
    light.position = middle
    let opacity = min(Float(look.brightness) * 0.55 * lit * boost, 0.85)
    if abs(opacity - poolOpacity) > 0.015,
      var material = pool?.model?.materials.first as? UnlitMaterial
    {
      poolOpacity = opacity
      material.blending = .transparent(opacity: .init(floatLiteral: opacity))
      pool?.model?.materials = [material]
    }
  }

  // MARK: - Sparks

  private struct Spark {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var age: Float
    var life: Float
    var size: Float
  }

  private func stepSparks(_ delta: Float) {
    let rate = Float(look.sparks) / ((Self.sparkLife.lowerBound + Self.sparkLife.upperBound) / 2)
    spawnDebt += rate * delta * (reduceMotion ? 0.5 : 1)
    while spawnDebt >= 1 {
      spawnDebt -= 1
      rise()
    }
    let target = finger.map { SIMD3($0.x, look.height * 0.45 + $0.y, 0) }
    for index in sparks.indices.reversed() {
      sparks[index].age += delta
      guard sparks[index].age < sparks[index].life else {
        sparks.remove(at: index)
        continue
      }
      guard sparks[index].age >= 0 else { continue }
      var spark = sparks[index]
      if let target {
        spark.velocity += (target - spark.position) * 1.2 * delta
      }
      // A little lift, a little drag, a little wander.
      spark.velocity.y += 0.25 * delta
      spark.velocity *= 1 - 0.9 * delta
      spark.velocity.x += Float(sin(Double(spark.age) * 5 + Double(index))) * 0.3 * delta
      spark.position += spark.velocity * delta
      sparks[index] = spark
    }
    for (index, model) in sparkModels.enumerated() {
      guard index < sparks.count, sparks[index].age >= 0 else {
        if model.isEnabled { model.isEnabled = false }
        continue
      }
      let spark = sparks[index]
      let fade = 1 - spark.age / spark.life
      model.isEnabled = true
      model.position = spark.position
      model.scale = .one * spark.size * fade
    }
  }

  /// One spark rising from the flame.
  private func rise() {
    guard sparks.count < Self.sparkPool else { return }
    let spread = look.width * 0.3
    sparks.append(
      Spark(
        position: [
          Float.random(in: -spread...spread), look.height * Float.random(in: 0.4...0.8),
          Float.random(in: -spread...spread),
        ],
        velocity: [Float.random(in: -0.15...0.15), Float.random(in: 0.5...0.95), 0],
        age: 0, life: Float.random(in: Self.sparkLife), size: Float.random(in: 0.7...1.2)))
  }

  /// `count` sparks thrown out from the flame's middle after `delay` seconds.
  private func throwSparks(_ count: Int, delay: Double) {
    for _ in 0..<count {
      guard sparks.count < Self.sparkPool else { return }
      let angle = Float.random(in: 0...(2 * .pi))
      let up = Float.random(in: 0.3...1)
      let speed = Float.random(in: 1.4...2.6)
      sparks.append(
        Spark(
          position: [0, look.height * 0.5, 0],
          velocity: [cos(angle) * speed * 0.7, up * speed, sin(angle) * speed * 0.35],
          age: -Float(delay) - Float.random(in: 0...0.15), life: Float.random(in: 1.4...2.2),
          size: Float.random(in: 0.9...1.5)))
    }
  }

  // MARK: - Glow

  private func updateGlows() {
    let point = middle
    guard let centre = view.project(point) else { return }
    let caught = Double(self.caught)
    let ember = Self.ember
    let lit = Double(look.isEmber ? 0.88 + 0.12 * sin(clock * 1.1) : Double(flicker))
    let boost = 1 + 0.8 * Double(swell) + 0.4 * Double(pulse)
    let brightness = (ember.brightness + (look.brightness - ember.brightness) * caught) * lit
    let reach = mix(ember.reach, look.reach, Float(caught))
    let warm = LightingLook.RGB.mix(look.mine, look.theirs, by: 0.5).genz
    var glows: [TabGlow] = [
      // The light the flame throws over the sill and the window.
      TabGlow(
        centre: centre, radius: view.reach(reach * 2.2, at: point), colour: warm,
        strength: 0.3 * brightness * boost),
      TabGlow(
        centre: centre, radius: view.reach(reach, at: point), colour: warm,
        strength: 0.55 * brightness * boost),
      TabGlow(
        centre: centre, radius: view.reach(max(look.width, 0.3) * 1.1, at: point),
        colour: look.core.genz, strength: min(0.75 * brightness * boost, 1)),
    ]
    // Each partner's tongue keeps a glow of its own colour on its side.
    for (colour, side) in [(look.mine, Float(-1)), (look.theirs, Float(1))] {
      let spot = point + SIMD3(side * look.width * 0.35, 0, 0)
      if let at = view.project(spot) {
        glows.append(
          TabGlow(
            centre: at, radius: view.reach(max(look.width, 0.3) * 1.6, at: spot),
            colour: colour.genz, strength: 0.32 * brightness * boost))
      }
    }
    screen.glows = glows
  }

  private func projectWindow() {
    let window = FlameLayout.window
    let back = -FlameLayout.wall
    let corners = [
      GenzRoomPoint(window.x0, back, window.z0), GenzRoomPoint(window.x1, back, window.z0),
      GenzRoomPoint(window.x1, back, window.z1), GenzRoomPoint(window.x0, back, window.z1),
    ]
    let now = corners.compactMap { view.project($0.scene) }
    let home = corners.compactMap { view.projectFromHome($0.scene) }
    let shown = now.count == 4 ? now : []
    if screen.window != shown { screen.window = shown }
    let homeShown = home.count == 4 ? home : []
    if screen.homeWindow != homeShown { screen.homeWindow = homeShown }
  }

  // MARK: - Building

  private func build() async {
    buildShell()
    buildWindow()
    buildSill()
    buildHolders()
    await Task.yield()
    buildFlame()
    buildSparks()
    light.components.set(
      PointLightComponent(
        color: GenzColour(0xFFB866).platformColour, intensity: 0, attenuationRadius: 6))
    room.addChild(light)
    if let environment = TabLook.ambient(top: GenzColour(0x4A4A6A), bottom: GenzColour(0x2A1E24)) {
      let ambient = Entity()
      ambient.components.set(
        ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.4))
      room.addChild(ambient)
      let receiver = ImageBasedLightReceiverComponent(imageBasedLight: ambient)
      self.receiver = receiver
      NookiDiorama.visit(room) { $0.components.set(receiver) }
    }
    isBuilt = true
    room.isEnabled = isOnScreen
    refresh()
    screen.isLit = true
  }

  /// Sets what follows the state rather than the clock: the holder, the colours and the light's
  /// reach.
  private func refresh() {
    let kind = FlameHolderKind(look.holder)
    for (holderKind, entity) in holders { entity.isEnabled = holderKind == kind }
    if case .hearth(let count) = look.holder {
      for (index, log) in logs.enumerated() { log.isEnabled = index < count }
    }
    light.components[PointLightComponent.self]?.attenuationRadius = look.lightReach
    light.components[PointLightComponent.self]?.color =
      LightingLook.RGB.mix(look.mine, look.theirs, by: 0.5).genz.platformColour
    paintFlame()
    if let pool {
      let size = 1.2 + look.reach * 0.9
      pool.scale = [size, 1, size * 0.7]
    }
    projectWindow()
  }

  private func buildShell() {
    let (width, height, wall) = (FlameLayout.width, FlameLayout.height, FlameLayout.wall)
    let window = FlameLayout.window
    let plaster = kit.matte(GenzColour(0x5A4048))
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
      kit.block(-wall, -wall, -wall, width + wall * 2, 5, wall, kit.matte(GenzColour(0x2E2024))))
  }

  private func buildWindow() {
    let window = FlameLayout.window
    let frame = kit.matte(GenzColour(0xE8D6BE))
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
    let sill = FlameLayout.sill
    let top = FlameLayout.sillTop
    let wood = kit.matte(GenzColour(0x8E5E40))
    room.addChild(
      kit.block(sill.x0, sill.y0, top - 0.28, sill.x1 - sill.x0, sill.y1 - sill.y0, 0.28, wood))
    room.addChild(
      kit.block(
        sill.x0 + 0.15, sill.y0, 0, sill.x1 - sill.x0 - 0.3, sill.y1 - sill.y0 - 0.25, top - 0.28,
        kit.matte(GenzColour(0x744832))))
    // A folded knit blanket at one end, and a small stack of books at the other.
    room.addChild(kit.block(0.35, 0.6, top, 1.5, 1.5, 0.22, kit.matte(GenzColour(0xC98A7E))))
    room.addChild(kit.block(0.45, 0.7, top + 0.22, 1.3, 1.3, 0.16, kit.matte(GenzColour(0xE0B0A2))))
    let books = kit.build(GenzPiece(.bookStack))
    let size = GenzPiece.Kind.bookStack.size
    let stack = Entity()
    stack.position = GenzRoomPoint(5.05, 1.9, top).scene
    stack.orientation = simd_quatf(angle: -0.35, axis: [0, 1, 0])
    stack.scale = .one * 1.2
    books.position = GenzRoomPoint(-size.x / 2, -size.y / 2, 0).scene
    stack.addChild(books)
    room.addChild(stack)
    // The warm pool of light the flame lays on the sill, under everything that stands on it.
    if let image = GenzGlow.falloff(pixels: 64),
      let texture = try? TextureResource(image: image, options: .init(semantic: .color))
    {
      var material = UnlitMaterial()
      material.color = .init(tint: GenzColour(0xFFB45A).platformColour, texture: .init(texture))
      material.blending = .transparent(opacity: .init(floatLiteral: 0.4))
      let pool = ModelEntity(
        mesh: .generatePlane(width: 1, depth: 1, cornerRadius: 0), materials: [material])
      pool.position = GenzRoomPoint(FlameLayout.holder.x, FlameLayout.holder.y, top + 0.006).scene
      room.addChild(pool)
      self.pool = pool
    }
    if let shadow = GenzGlow.shadow(width: 1.6, depth: 1.3) {
      shadow.position =
        GenzRoomPoint(FlameLayout.holder.x, FlameLayout.holder.y, top + 0.012).scene
      room.addChild(shadow)
    }
  }

  private func buildHolders() {
    let base = FlameLayout.holder.scene
    let clay = kit.matte(GenzColour(0xB86E4C))
    let clayLight = kit.matte(GenzColour(0xD08A62))
    let wax = kit.matte(GenzColour(0xF4E4CC))
    let wick = kit.matte(GenzColour(0x3A2A24))

    // The saucer every small flame sits in.
    func saucer() -> Entity {
      let dish = Entity()
      dish.addChild(kit.part(kit.prism(sides: 14, radius: 0.5, top: 0.62, height: 0.16), clay))
      dish.addChild(
        kit.part(
          kit.prism(sides: 14, radius: 0.5, top: 0.5, height: 0.02), clayLight, at: [0, 0.15, 0]))
      return dish
    }

    let dish = saucer()
    dish.position = base
    holders[.dish] = dish

    let candle = saucer()
    candle.position = base
    candle.addChild(
      kit.part(kit.prism(sides: 12, radius: 0.24, top: 0.23, height: 0.78), wax, at: [0, 0.16, 0]))
    candle.addChild(
      kit.part(
        kit.prism(sides: 12, radius: 0.19, top: 0.19, height: 0.01), kit.matte(GenzColour(0xFFF4E2)),
        at: [0, 0.94, 0]))
    candle.addChild(kit.part(kit.box([0.03, 0.1, 0.03]), wick, at: [0, 0.98, 0]))
    holders[.candle] = candle

    let lantern = Entity()
    lantern.position = base
    let iron = kit.matte(GenzColour(0x3A302E))
    let brass = kit.matte(GenzColour(0xB08A50))
    lantern.addChild(kit.part(kit.prism(sides: 4, radius: 0.78, top: 0.74, height: 0.14), iron))
    lantern.addChild(
      kit.part(kit.prism(sides: 12, radius: 0.24, top: 0.23, height: 0.8), wax, at: [0, 0.14, 0]))
    lantern.addChild(kit.part(kit.box([0.03, 0.1, 0.03]), wick, at: [0, 0.98, 0]))
    let post: Float = 0.5
    for corner in [SIMD2<Float>(-1, -1), [1, -1], [1, 1], [-1, 1]] {
      lantern.addChild(
        kit.part(kit.box([0.07, 2.3, 0.07]), iron, at: [corner.x * post, 1.27, corner.y * post]))
    }
    // Panes of warm glass between the posts, so the lantern glows when lit.
    let glass = kit.glow(GenzColour(0xFFD9A0), opacity: 0.14)
    for side in 0..<4 {
      let angle = Float(side) * .pi / 2
      lantern.addChild(
        kit.part(
          kit.plane(width: post * 2, height: 2.2), glass,
          at: [sin(angle) * post, 1.27, cos(angle) * post],
          turn: simd_quatf(angle: angle, axis: [0, 1, 0])))
    }
    lantern.addChild(
      kit.part(kit.prism(sides: 4, radius: 0.8, top: 0.2, height: 0.5), iron, at: [0, 2.42, 0]))
    lantern.addChild(
      kit.part(kit.prism(sides: 10, radius: 0.12, top: 0.12, height: 0.08), brass, at: [0, 2.9, 0]))
    holders[.lantern] = lantern

    let hearth = Entity()
    hearth.position = base
    hearth.addChild(
      kit.part(kit.prism(sides: 16, radius: 0.8, top: 1.05, height: 0.42), clay))
    hearth.addChild(
      kit.part(
        kit.prism(sides: 16, radius: 0.9, top: 0.9, height: 0.03), clayLight, at: [0, 0.41, 0]))
    let bark = [kit.matte(GenzColour(0x5C3A28)), kit.matte(GenzColour(0x74482E))]
    for index in 0..<4 {
      let turn = Float(index) * .pi / 4 + 0.3
      let log = kit.part(
        kit.prism(sides: 7, radius: 0.12, top: 0.1, height: 1.35), bark[index % 2],
        at: [0, 0.5 + Float(index) * 0.05, 0],
        turn: simd_quatf(angle: turn, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
      // The prism stands on its end; lying down, it is moved back by half its length.
      log.position += simd_quatf(angle: turn, axis: [0, 1, 0]).act([0, 0, -0.67])
      hearth.addChild(log)
      logs.append(log)
    }
    holders[.hearth] = hearth

    for holder in holders.values {
      holder.isEnabled = false
      room.addChild(holder)
    }
  }

  private func buildFlame() {
    let tongue = Self.tongueMesh(kit)
    mineTongue.addChild(ModelEntity(mesh: tongue, materials: [kit.glow(GenzColour(0xFFC25A))]))
    theirsTongue.addChild(ModelEntity(mesh: tongue, materials: [kit.glow(GenzColour(0xFF8F7A))]))
    coreTongue.addChild(ModelEntity(mesh: tongue, materials: [kit.glow(GenzColour(0xFFF2D6))]))
    coreTongue.position = [0, 0.02, 0.02]
    coal.addChild(
      kit.part(
        kit.prism(sides: 7, radius: 0.22, top: 0.12, height: 0.14), kit.glow(GenzColour(0xF07A3A))))
    coal.addChild(
      kit.part(
        kit.prism(sides: 7, radius: 0.12, top: 0.05, height: 0.17), kit.glow(GenzColour(0xFFC27A))))
    coal.position = [0, -0.04, 0]
    for part in [mineTongue, theirsTongue, coreTongue, coal] { flame.addChild(part) }
    flame.name = Self.flameName
    room.addChild(flame)
  }

  private func buildSparks() {
    let materials = [kit.glow(GenzColour(0xFFE6B0)), kit.glow(GenzColour(0xFFB45E))]
    let mesh = kit.box([0.06, 0.06, 0.06])
    for index in 0..<Self.sparkPool {
      let model = ModelEntity(mesh: mesh, materials: [materials[index % 2]])
      model.isEnabled = false
      flame.addChild(model)
      sparkModels.append(model)
    }
  }

  /// Gives the tongues this look's colours, when they have changed.
  private func paintFlame() {
    if let paintedLook, paintedLook.mine == look.mine, paintedLook.theirs == look.theirs,
      paintedLook.core == look.core
    {
      return
    }
    paintedLook = look
    for (tongue, colour) in [(mineTongue, look.mine), (theirsTongue, look.theirs)] {
      (tongue.children.first as? ModelEntity)?.model?.materials = [
        kit.glow(colour.genz, opacity: 0.88)
      ]
    }
    (coreTongue.children.first as? ModelEntity)?.model?.materials = [kit.glow(look.core.genz)]
  }

  /// A flame's tongue one unit tall and one across at its widest: a teardrop turned about its
  /// axis, round at the foot and drawn up to a point.
  static func tongueMesh(_ kit: GenzKit) -> MeshResource {
    kit.cached("flame tongue") {
      let sides = 10
      let rings = 9
      func radius(_ along: Float) -> Float {
        0.5 * sin(.pi * pow(along, 0.62))
      }
      var faces = GenzFaces()
      let ring = (0..<sides).map { index -> SIMD2<Float> in
        let angle = Float(index) * 2 * .pi / Float(sides)
        return SIMD2(cos(angle), sin(angle))
      }
      for step in 0..<rings {
        let low = Float(step) / Float(rings)
        let high = Float(step + 1) / Float(rings)
        let (r0, r1) = (radius(low), radius(high))
        for index in 0..<sides {
          let a = ring[index]
          let b = ring[(index + 1) % sides]
          let p0 = SIMD3(a.x * r0, low, a.y * r0)
          let p1 = SIMD3(b.x * r0, low, b.y * r0)
          let p2 = SIMD3(b.x * r1, high, b.y * r1)
          let p3 = SIMD3(a.x * r1, high, a.y * r1)
          if step == 0 {
            faces.fan([p0, p3, p2])
          } else if step == rings - 1 {
            faces.fan([p0, p3, p1])
          } else {
            faces.quad(p0, p3, p2, p1)
          }
        }
      }
      return faces.mesh()
    }
  }

  private func mix(_ from: Float, _ to: Float, _ amount: Float) -> Float {
    from + (to - from) * min(max(amount, 0), 1)
  }
}

/// The holders by kind, without the hearth's count of logs.
private enum FlameHolderKind: Hashable {
  case dish, candle, lantern, hearth

  init(_ holder: FlameHolder) {
    switch holder {
    case .dish: self = .dish
    case .candle: self = .candle
    case .lantern: self = .lantern
    case .hearth: self = .hearth
    }
  }
}
