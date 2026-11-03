import CoreGraphics
import Foundation
import OSLog
import PetScene
import RealityKit

/// The first-launch scene: a deep windowsill at night with candles at both ends, fairy lights
/// down the sides of the window, and a soft glossy heart floating over a cushion in the middle,
/// beating gently. The camera glides in out of the dark while the lights come on. Built from the
/// styled rooms' materials and smooth lathed and rounded meshes; only the heart loads from a file.
@MainActor
final class OnboardingStage: TabStage {
  static let heartName = "onboarding-heart"
  static let tagName = "onboarding-tag"

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
  private var state = OnboardingSceneState(moment: .resting)
  private var moment: OnboardingSceneState.Moment { state.moment }
  private var hasArrived = false
  private var squeezedAt: Double?
  private var halves = HeartHalves()
  /// The halves of the model by side, each with the place it was made at.
  private var halfEntities: [HeartSide: (entity: Entity, home: SIMD3<Float>)] = [:]
  /// How much the model is scaled, to turn room units into its own.
  private var heartScale: Float = 1
  /// When the halves last met, for the burst of light.
  private var burstAt: Double?

  /// The little paper tag with the code, and how far it has come up.
  private let tag = Entity()
  private var tagCode: String?
  private var tagShown: Float = 0

  /// Floats and sways; holds `beat`.
  private let heartFloat = Entity()
  /// Swells with the beat and squishes when tapped; holds the model.
  private let heartBeat = Entity()
  private var heartMaterial: PhysicallyBasedMaterial?
  /// The heart's models, found once, so the beat's glow does not walk the heart every frame.
  private var heartModels: [ModelEntity] = []
  /// The glow last given to the heart's material, which is only written again once it has moved
  /// by more than the eye can see.
  private var heartGlow: Float?
  /// The opacities last set, so that unchanged ones are not written every frame.
  private var opacities: [ObjectIdentifier: Float] = [:]
  private var flames: [Entity] = []

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "OnboardingStage")
  private static let flameColour = GenzColour(0xFFC46B)
  private static let beadColour = GenzColour(0xFFE2B0)
  private static let heartColour = GenzColour(0xFF6F7E)
  /// How much faster the rest of the flight runs once it is cut short.
  private static let hurry = 7.0
  /// Changes smaller than these do not show, so they are not written.
  private static let unseenGlow: Float = 0.004
  private static let unseenOpacity: Float = 0.002

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
    self.state = state
    hasArrived = false
    squeezedAt = nil
    burstAt = nil
    flightTime = state.moment == .arriving ? 0 : timeline.duration
    halves.settle(state.moment, mine: state.mine)
    tagShown = state.code == nil ? 0 : 1
    if isBuilt {
      setTag(state.code)
      apply(flightTime)
    }
  }

  /// Follows a change of `state`: anything past arriving cuts a flight short, and the halves and
  /// the tag move to their places from wherever they are.
  func show(_ state: OnboardingSceneState) {
    guard state != self.state else { return }
    self.state = state
    if isBuilt {
      setTag(state.code)
      apply(flightTime)
    }
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
    guard hasArrived else { return }
    if TabLook.named(Self.tagName, from: entity) != nil, tagShown > 0.5 {
      onEvent?(.codeTapped)
    } else if TabLook.named(Self.heartName, from: entity) != nil {
      if !reduceMotion { squeezedAt = clock }
      onEvent?(.heartTapped)
    }
  }

  // MARK: - Stepping

  private func tick(_ delta: TimeInterval) {
    clock += delta
    lighting.step(delta)
    guard isBuilt else { return }
    if flightTime < timeline.duration {
      let rate = moment == .arriving ? 1 : Self.hurry
      flightTime = min(flightTime + delta * rate, timeline.duration)
    }
    if halves.step(delta, towards: moment, mine: state.mine, reduceMotion: reduceMotion) {
      burstAt = clock
      onEvent?(.joined)
    }
    let wantedTag: Float = state.code == nil ? 0 : 1
    tagShown += (wantedTag - tagShown) * Float(1 - exp(-(reduceMotion ? 6 : 4) * delta))
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
    let darkness = timeline.darkness(time)
    // Every write invalidates the view over the scene, even of the same value.
    if screen.darkness != darkness { screen.darkness = darkness }
    lighting.setDimmer(timeline.warmth(time))
    stepHeart(time)
    stepHalves()
    stepTag()
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
      let intensity = (0.12 + 0.3 * glow) * (1 + 0.25 * beat) + 0.9 * burst
      if let heartGlow, abs(intensity - heartGlow) < Self.unseenGlow { return }
      heartGlow = intensity
      material.emissiveIntensity = intensity
      heartMaterial = material
      setHeartMaterial(material)
    }
  }

  /// How strong the burst of light is now, from 1 as the halves meet down to 0.
  private var burst: Float {
    guard let burstAt else { return 0 }
    let age = clock - burstAt
    guard age >= 0, age < OnboardingBurst.length else { return 0 }
    return Float(OnboardingBurst.strength(age))
  }

  private func stepHalves() {
    let poses = [(state.mine, halves.me), (state.mine.other, halves.partner)]
    for (side, pose) in poses {
      guard let half = halfEntities[side] else { continue }
      var opacity = pose.opacity
      if side == state.mine.other, moment == .apart(partner: .waiting), !reduceMotion {
        opacity *= 0.85 + 0.25 * Float(sin(clock * 2.4))
      }
      half.entity.position = half.home + pose.offset / heartScale
      half.entity.orientation = simd_quatf(angle: pose.tilt, axis: [0, 0, 1])
      setOpacity(min(max(opacity, 0), 1), of: half.entity)
      half.entity.isEnabled = opacity > 0.01
    }
  }

  private func stepTag() {
    tag.isEnabled = tagShown > 0.01
    let pop = reduceMotion ? 1 : 0.6 + 0.4 * tagShown
    tag.scale = .one * pop
    setOpacity(tagShown, of: tag)
  }

  private func setOpacity(_ opacity: Float, of entity: Entity) {
    let key = ObjectIdentifier(entity)
    if let last = opacities[key], abs(last - opacity) < Self.unseenOpacity { return }
    opacities[key] = opacity
    entity.components.set(OpacityComponent(opacity: opacity))
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
    // The partner's half, waiting: a soft glow of its own that breathes.
    let partner = Double(halves.partner.opacity)
    if partner > 0.01, simd_length(halves.partner.offset) > 0.3 {
      let spot = point + halves.partner.offset
      if let centre = view.project(spot) {
        let breath = reduceMotion ? 1 : 0.75 + 0.35 * sin(clock * 2.4)
        glows.append(
          TabGlow(
            centre: centre, radius: view.reach(OnboardingLayout.heartHeight * 1.3, at: spot),
            colour: GenzColour(0xFFB08A), strength: 0.45 * partner * breath * halos))
      }
    }
    if let burstAt, let centre = view.project(point) {
      let age = clock - burstAt
      if age < OnboardingBurst.length {
        let strength = OnboardingBurst.strength(age)
        let spread = reduceMotion ? 3.2 : OnboardingBurst.spread(age)
        glows.append(
          TabGlow(
            centre: centre, radius: view.reach(Float(spread), at: point),
            colour: GenzColour(0xFFC88A), strength: 0.9 * strength))
        glows.append(
          TabGlow(
            centre: centre, radius: view.reach(1.4, at: point), colour: GenzColour(0xFFF3DC),
            strength: strength))
      }
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
    buildTag()
    lighting.apply(look)
    isBuilt = true
    room.isEnabled = isOnScreen
    screen.isLit = true
    setTag(state.code)
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
          LowPoly.sphere(radius: star.size / 2, segments: 8), kit.glow(GenzColour(0xFFF4DA)),
          at: GenzRoomPoint(star.x, -0.42, star.z).scene))
    }
    // A round moon, flattened against the glass.
    let moon = OnboardingLayout.moon
    let disc = kit.part(
      LowPoly.sphere(radius: moon.radius, segments: 48), kit.glow(GenzColour(0xFFEFC8)),
      at: GenzRoomPoint(moon.x, -0.42, moon.z).scene)
    disc.scale = [1, 1, 0.1]
    room.addChild(disc)
    // The frame and the cross of its bars, their edges softly rounded.
    let frame = kit.matte(GenzColour(0xF0DCC0))
    let bar: Float = 0.2
    let span = window.x1 - window.x0
    let rise = window.z1 - window.z0
    room.addChild(soft(window.x0 - bar, -0.1, window.z1, span + bar * 2, 0.3, bar, frame))
    room.addChild(soft(window.x0 - bar, -0.1, window.z0 - bar, span + bar * 2, 0.3, bar, frame))
    room.addChild(soft(window.x0 - bar, -0.1, window.z0 - bar, bar, 0.3, rise + bar * 2, frame))
    room.addChild(soft(window.x1, -0.1, window.z0 - bar, bar, 0.3, rise + bar * 2, frame))
    let middle = (window.x0 + window.x1) / 2
    room.addChild(soft(middle - 0.06, -0.3, window.z0, 0.12, 0.1, rise, frame, radius: 0.04))
    room.addChild(
      soft(
        window.x0, -0.3, (window.z0 + window.z1) / 2 - 0.06, span, 0.1, 0.12, frame, radius: 0.04))
  }

  /// A box like ``GenzKit/block(_:_:_:_:_:_:_:)`` with its edges rounded, so it catches the light
  /// along them instead of meeting it at a hard corner.
  private func soft(
    _ x: Float, _ y: Float, _ z: Float, _ w: Float, _ d: Float, _ h: Float,
    _ material: any RealityKit.Material, radius: Float = 0.07
  ) -> ModelEntity {
    kit.part(
      LowPoly.roundedBox([w, h, d], radius: radius),
      material, at: GenzRoomPoint(x + w / 2, y + d / 2, z + h / 2).scene)
  }

  private func buildSill() {
    let sill = OnboardingLayout.sill
    let top = OnboardingLayout.sillTop
    let wood = kit.matte(GenzColour(0x9A6644))
    room.addChild(
      soft(
        sill.x0, sill.y0 - 0.1, top - 0.28, sill.x1 - sill.x0, sill.y1 - sill.y0 + 0.1, 0.28, wood,
        radius: 0.1))
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
        LowPoly.lathe(
          "cushion",
          profile: [
            [0, 0], [0.74, 0], [0.84, 0.04], [0.87, 0.13], [0.82, 0.22], [0.7, 0.27], [0, 0.28],
          ], segments: 48),
        kit.matte(GenzColour(0xE6A2A0)), at: cushion.scene + [0, 0.03, 0]))
    room.addChild(
      kit.part(
        LowPoly.lathe(
          "cushion top",
          profile: [[0, 0], [0.62, 0], [0.68, 0.04], [0.6, 0.09], [0.3, 0.11], [0, 0.11]],
          segments: 48),
        kit.matte(GenzColour(0xF1BDB6)), at: cushion.scene + [0, 0.25, 0]))
    // A small stack of books at the back, and a sprig in a glass jar.
    room.addChild(books(at: GenzRoomPoint(5.0, 2.2, top)))
    let jar = GenzRoomPoint(0.75, 0.55, top).scene
    room.addChild(
      kit.part(
        LowPoly.lathe(
          "jar",
          profile: [
            [0, 0], [0.19, 0], [0.22, 0.04], [0.22, 0.38], [0.17, 0.46], [0.18, 0.5], [0, 0.5],
          ], segments: 32),
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
          LowPoly.sphere(radius: 0.08, segments: 12),
          kit.matte(GenzColour(index == 1 ? 0xF4C6C0 : 0xFFE3B0)),
          at: jar + [Float(index - 1) * 0.07 - sin(lean) * 0.45, 1.22, 0]))
    }
  }

  /// Three books lying in a loose stack, each a soft-cornered cover around a block of pages.
  private func books(at spot: GenzRoomPoint) -> Entity {
    let stack = Entity()
    stack.position = spot.scene
    stack.orientation = simd_quatf(angle: -0.4, axis: [0, 1, 0])
    let pages = kit.matte(GenzColour(0xF4EAD6))
    let books: [(size: SIMD3<Float>, colour: UInt32, turn: Float)] = [
      ([0.95, 0.13, 0.7], 0x4F6B8A, 0), ([0.85, 0.11, 0.62], 0xB5654F, 0.12),
      ([0.76, 0.1, 0.55], 0xD8C7A6, -0.08),
    ]
    var height: Float = 0
    for book in books {
      let entity = Entity()
      entity.position = [0, height + book.size.y / 2, 0]
      entity.orientation = simd_quatf(angle: book.turn, axis: [0, 1, 0])
      entity.addChild(
        kit.part(
          LowPoly.roundedBox(book.size, radius: 0.035), kit.matte(GenzColour(book.colour))))
      // The pages show along the three open sides.
      entity.addChild(
        kit.part(
          LowPoly.roundedBox(
            [book.size.x - 0.06, book.size.y - 0.06, book.size.z - 0.02], radius: 0.02),
          pages, at: [0.04, 0, 0]))
      stack.addChild(entity)
      height += book.size.y
    }
    return stack
  }

  private func buildCandles() {
    let wax = kit.matte(GenzColour(0xF6E7D2))
    let wick = kit.matte(GenzColour(0x3A2A24))
    for candle in OnboardingLayout.candles {
      let base = candle.spot.scene
      let (r, h) = (candle.radius, candle.height)
      // A soft shoulder at the top, dipping into a little melted pool round the wick.
      room.addChild(
        kit.part(
          LowPoly.lathe(
            "candle \(r) \(h)",
            profile: [
              [0, 0], [r - 0.02, 0], [r, 0.03], [r * 0.98, h - 0.07], [r * 0.93, h - 0.01],
              [r * 0.8, h], [r * 0.5, h - 0.03], [0, h - 0.04],
            ]),
          wax, at: base))
      room.addChild(
        kit.part(
          LowPoly.cylinder(height: 0.14, radius: 0.016, segments: 8), wick,
          at: base + [0, h + 0.03, 0]))
      let flame = Entity()
      flame.position = base + [0, h + 0.06, 0]
      flame.addChild(
        kit.part(
          LowPoly.lathe(
            "flame",
            profile: [
              [0, 0], [0.06, 0.03], [0.09, 0.11], [0.07, 0.22], [0.03, 0.31], [0, 0.36],
            ],
            segments: 16),
          kit.glow(Self.flameColour)))
      flame.addChild(
        kit.part(
          LowPoly.lathe(
            "flame core",
            profile: [[0, 0], [0.04, 0.03], [0.05, 0.08], [0.03, 0.15], [0, 0.2]],
            segments: 12),
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
          LowPoly.lathe(
            "bulb",
            profile: [
              [0, 0], [0.04, 0.01], [0.075, 0.06], [0.06, 0.12], [0.03, 0.14], [0, 0.14],
            ],
            segments: 12),
          materials[index % 2], at: bead.scene))
    }
    // The wire between them, along each strand.
    let wire = kit.matte(GenzColour(0x2E2420))
    for strand in OnboardingLayout.strands {
      for (from, to) in zip(strand, strand.dropFirst()) {
        let a = from.scene
        let b = to.scene
        room.addChild(
          kit.part(
            kit.box([0.02, 0.02, simd_distance(a, b)]), wire, at: (a + b) / 2,
            turn: simd_quatf(from: [0, 0, 1], to: simd_normalize(b - a))))
      }
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
        Self.beadColour, intensity: 4_000, reach: 5, at: GenzRoomPoint(3, 1.0, 6.4)))
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

  // MARK: - Tag

  private func buildTag() {
    let spec = OnboardingLayout.tag
    tag.name = Self.tagName
    tag.position = spec.foot.scene
    tag.orientation =
      simd_quatf(angle: spec.yaw, axis: [0, 1, 0]) * simd_quatf(angle: -spec.lean, axis: [1, 0, 0])
    tag.isEnabled = false
    room.addChild(tag)
    NookiDiorama.makeTappable(
      tag, size: [spec.width + 0.3, spec.height + 0.3, 0.3], center: [0, spec.height / 2, 0])
  }

  /// Writes `code` on the tag, or leaves the tag as it is while it fades out.
  private func setTag(_ code: String?) {
    guard let code, code != tagCode else { return }
    tagCode = code
    let spec = OnboardingLayout.tag
    for child in Array(tag.children) { child.removeFromParent() }
    // A card a little thicker than paper, and the face with the code on it.
    tag.addChild(
      kit.part(
        kit.box([spec.width, spec.height, 0.04]), kit.matte(GenzColour(0xF3E2C8)),
        at: [0, spec.height / 2, -0.025]))
    let face: any RealityKit.Material =
      OnboardingTag.image(code: code).flatMap { TabLook.picture($0, tint: GenzColour(0xF8EBDA)) }
      ?? kit.matte(GenzColour(0xFFF6EA))
    tag.addChild(
      kit.part(
        kit.plane(width: spec.width, height: spec.height), face, at: [0, spec.height / 2, 0]))
    if let receiver { NookiDiorama.visit(tag) { $0.components.set(receiver) } }
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
    heartScale = scale
    for (side, name) in [(HeartSide.left, "heart_L"), (.right, "heart_R")] {
      if let half = model.findEntity(named: name) {
        halfEntities[side] = (half, half.position)
      }
    }
    setHeartMaterial(material)
    if let receiver { NookiDiorama.visit(model) { $0.components.set(receiver) } }
    heartFloat.name = Self.heartName
    let reach = OnboardingLayout.heartHeight
    NookiDiorama.makeTappable(heartFloat, size: [reach * 1.4, reach * 1.2, reach], center: .zero)
  }

  private func setHeartMaterial(_ material: PhysicallyBasedMaterial) {
    if heartModels.isEmpty {
      NookiDiorama.visit(heartBeat) { entity in
        if let model = entity as? ModelEntity, model.model?.materials.isEmpty == false {
          heartModels.append(model)
        }
      }
    }
    for model in heartModels {
      guard let count = model.model?.materials.count else { continue }
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
    let mesh = LowPoly.sphere(radius: 0.5, segments: 24)
    for side: Float in [-1, 1] {
      let half = ModelEntity(mesh: mesh, materials: [SimpleMaterial()])
      half.name = side < 0 ? "heart_L" : "heart_R"
      half.position = [side * 0.32, 0.1, 0]
      half.scale = [0.85, 1, 0.8]
      heart.addChild(half)
    }
    return heart
  }
}
