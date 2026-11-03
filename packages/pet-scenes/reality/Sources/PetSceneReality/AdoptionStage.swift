import CoreGraphics
import Foundation
import OSLog
import Observation
import Pet
import PetScene
import RealityKit

/// Where the marks over the cats go, in the view's points, so the flat layer can draw each
/// partner's pick and the rings of the agreed cat over the 3D scene.
@MainActor
@Observable
final class AdoptionMarks {
  /// Over each cat's head, left to right.
  var heads: [CGPoint] = []
  /// The middle of each cat's body.
  var bodies: [CGPoint] = []
  /// About half a cat's length, in points, at each cat.
  var sizes: [CGFloat] = []
}

/// Choosing the cat together: five cats on cushions in a cosy corner at night, candles on the
/// floor and fairy lights over the window. A picked cat comes forward, the two candidates of a
/// bid step out and play, the adopted cat greets the pair and then walks out with the camera
/// after it. Built from the styled rooms' shared meshes; only the cats load from files.
@MainActor
final class AdoptionStage: TabStage {
  static let catPrefix = "adoption-cat:"
  private static let seatName = "adoption-seat"

  let root = Entity()
  let screen = TabScreen()
  let marks = AdoptionMarks()
  var onEvent: ((AdoptionSceneEvent) -> Void)?

  private let kit: GenzKit
  private let cats: GenzCatSource
  private let room = Entity()
  private let view: TabCamera
  private let frames = FrameClock()
  private var building: Task<Void, Never>?
  private var isBuilt = false
  private var isOnScreen = false
  private var reduceMotion = false
  private var clock = 0.0
  private var receiver: ImageBasedLightReceiverComponent?
  private let lighting = TabLighting()
  private var look = LightingLook.off
  private var state = AdoptionSceneState(cats: [])

  private var holders: [Entity] = []
  private var rigs: [CatRig?] = []
  private var shown: [CatChoice?] = []
  private var loads: [Task<Void, Never>?] = []
  private var forward: [Float] = []
  /// Until when each cat is busy with a move, on the stage's clock.
  private var busyUntil: [Double] = []
  /// When the adopted cat started walking out.
  private var leftAt: Double?
  private var hasLeft = false

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "AdoptionStage")
  private static let flameColour = GenzColour(0xFFB45A)
  private static let beadColour = GenzColour(0xFFD9A0)
  private static let cushionColours: [UInt32] = [0xC9786A, 0xE0A86A, 0x9F7AA8, 0xD98C8C, 0x7FA08E]
  private static let forwardRate: Float = 2.2

  init(kit: GenzKit, cats: GenzCatSource) {
    self.kit = kit
    self.cats = cats
    view = TabCamera(home: AdoptionLayout.camera)
    root.addChild(room)
    root.addChild(view.lens)
    room.isEnabled = false
  }

  // MARK: - Showing

  /// Opens the scene afresh for `state`: the cats back on their cushions and the camera home.
  func begin(_ state: AdoptionSceneState) {
    leftAt = nil
    hasLeft = false
    screen.darkness = 0
    view.fly(yaw: 0, pitch: 0, distance: 1)
    forward = AdoptionLayout.forward(state)
    busyUntil = Array(repeating: 0, count: state.cats.count)
    self.state = AdoptionSceneState(cats: [])
    show(state)
  }

  func show(_ state: AdoptionSceneState) {
    guard state != self.state else { return }
    let before = self.state
    self.state = state
    if forward.count != state.cats.count {
      forward = AdoptionLayout.forward(state)
      busyUntil = Array(repeating: 0, count: state.cats.count)
    }
    if state.moment != before.moment {
      busyUntil = Array(repeating: 0, count: state.cats.count)
      if state.moment == .leaving, leftAt == nil { leftAt = clock }
    }
    if isBuilt, state.cats != before.cats { placeCats() }
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
  }

  func setLighting(_ look: LightingLook) {
    guard look != self.look else { return }
    self.look = look
    guard isBuilt else { return }
    lighting.apply(look)
    updateGlows()
  }

  func fit(to size: CGSize) {
    view.fit(to: size)
    updateGlows()
    updateMarks()
  }

  func orbit(byX deltaX: Float, y deltaY: Float) {
    guard leftAt == nil else { return }
    view.orbit(byX: deltaX, y: deltaY)
    updateGlows()
    updateMarks()
  }

  func endOrbit(velocityX: Float, velocityY: Float) {
    guard leftAt == nil else { return }
    view.release(animated: !reduceMotion)
  }

  func tap(_ entity: Entity) {
    guard state.moment == .choosing,
      let (_, raw) = TabLook.named(Self.catPrefix, from: entity), let index = Int(raw),
      index < state.cats.count
    else { return }
    if !reduceMotion, clock >= busyUntil[index] { perform(.perk, cat: index) }
    onEvent?(.tapped(index))
  }

  // MARK: - Stepping

  private func tick(_ delta: TimeInterval) {
    clock += delta
    lighting.step(delta)
    var moved = view.step(Float(delta))
    let wanted = AdoptionLayout.forward(state)
    for index in forward.indices where index < wanted.count {
      let target = wanted[index]
      guard forward[index] != target else { continue }
      let step = reduceMotion ? 1 : Self.forwardRate * Float(delta)
      forward[index] =
        target > forward[index]
        ? min(forward[index] + step, target) : max(forward[index] - step, target)
      moved = true
    }
    if let leftAt { moved = stepExit(clock - leftAt) || moved }
    if moved {
      placeHolders()
      updateGlows()
    }
    if moved || !marks.heads.isEmpty { updateMarks() }
    stepActs()
  }

  private func stepExit(_ time: TimeInterval) -> Bool {
    let darkness = AdoptionExit.darkness(at: time, reduceMotion: reduceMotion)
    // Every write invalidates the view over the scene, even of the same value.
    if screen.darkness != darkness { screen.darkness = darkness }
    if !reduceMotion {
      let flight = AdoptionExit.flight(at: time)
      view.fly(yaw: flight.x, pitch: flight.y, distance: flight.z)
    }
    if !hasLeft, AdoptionExit.isDone(at: time, reduceMotion: reduceMotion) {
      hasLeft = true
      onEvent?(.left)
    }
    return true
  }

  private func placeHolders() {
    for (index, holder) in holders.enumerated() where index < forward.count {
      if let leftAt, index == state.adopted, !reduceMotion {
        holder.position = AdoptionExit.spot(from: index, at: clock - leftAt).scene
        holder.orientation = simd_quatf(
          angle: AdoptionExit.heading(from: index), axis: [0, 1, 0])
      } else {
        holder.position = AdoptionLayout.spot(index, forward: forward[index]).scene
        holder.orientation = simd_quatf(angle: AdoptionLayout.heading(index), axis: [0, 1, 0])
      }
    }
  }

  /// Keeps each cat doing what its part in the scene asks.
  private func stepActs() {
    let acts = AdoptionLayout.acts(state)
    for (index, act) in acts.enumerated() where index < rigs.count {
      guard let rig = rigs[index] else { continue }
      if act == .walk {
        rig.play(reduceMotion ? .sit : .walk)
        continue
      }
      if act == .agreed || act == .greet { rig.look(at: view.position, weight: 0.8) }
      guard clock >= busyUntil[index] else { continue }
      switch act {
      case .sit:
        if !reduceMotion, Double.random(in: 0..<1) < 0.004 {
          perform(
            [.blink, .tailFlick, .look, .groom, .slowBlink].randomElement() ?? .blink, cat: index)
        } else if rig.current != .sit || !rig.isPlaying {
          rig.play(.sit)
        }
      case .bid(let playful):
        if reduceMotion {
          rig.play(.sit)
        } else if playful {
          perform(rig.current == .crouchWiggle ? .pounce : .crouchWiggle, cat: index, rest: 0.4)
        } else {
          perform(.headbutt, cat: index, rest: 1.2)
        }
      case .agreed:
        if rig.current == .perk { rig.play(.sit) } else { perform(.perk, cat: index, rest: 2.5) }
      case .greet:
        if rig.current == .happy { rig.play(.sit) } else { perform(.happy, cat: index, rest: 4) }
      case .settle:
        rig.play(.sleep)
      case .walk:
        break
      }
    }
  }

  /// Plays `action`, or its first stand-in this cat has, and keeps the cat busy until it ends and
  /// `rest` seconds after.
  private func perform(_ action: CatAction, cat index: Int, rest: Double = 0) {
    guard let rig = rigs[index] else { return }
    let move = ([action] + action.standIns).first { rig.info[$0] != nil } ?? .sit
    rig.play(move)
    let length = rig.duration(of: move).flatMap { $0.isFinite ? $0 : nil } ?? 2
    busyUntil[index] = clock + length + rest
  }

  // MARK: - Overlays

  private func updateMarks() {
    var heads: [CGPoint] = []
    var bodies: [CGPoint] = []
    var sizes: [CGFloat] = []
    for holder in holders {
      let base = holder.position
      let head = base + [0, AdoptionLayout.headHeight, 0]
      let body = base + [0, AdoptionLayout.bodyHeight, 0]
      guard let headPoint = view.project(head), let bodyPoint = view.project(body) else {
        heads.append(CGPoint(x: -100, y: -100))
        bodies.append(CGPoint(x: -100, y: -100))
        sizes.append(0)
        continue
      }
      heads.append(headPoint)
      bodies.append(bodyPoint)
      sizes.append(view.reach(AdoptionLayout.catLength * 0.5, at: body))
    }
    if heads != marks.heads { marks.heads = heads }
    if bodies != marks.bodies { marks.bodies = bodies }
    if sizes != marks.sizes { marks.sizes = sizes }
  }

  private func updateGlows() {
    var glows: [TabGlow] = []
    let halos = lighting.haloScale
    for (index, candle) in AdoptionLayout.candles.enumerated() {
      let flame = GenzRoomPoint(candle.x, candle.y, 0.9).scene
      guard let centre = view.project(flame) else { continue }
      let flicker = reduceMotion ? 1 : GlowLights.flicker(0.15, time: clock + Double(index) * 1.3)
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(2.4, at: flame),
          colour: lighting.tint(Self.flameColour), strength: 0.5 * halos * flicker))
    }
    for bead in AdoptionLayout.beads {
      let point = bead.scene
      guard let centre = view.project(point) else { continue }
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(0.42, at: point),
          colour: lighting.fairyColour ?? Self.beadColour, strength: 0.5 * halos))
    }
    let window = AdoptionLayout.window
    let pane = GenzRoomPoint((window.x0 + window.x1) / 2, 0, (window.z0 + window.z1) / 2).scene
    if let centre = view.project(pane) {
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(3.2, at: pane), colour: GenzColour(0x8FA0E0),
          strength: 0.12 * halos))
    }
    screen.glows = glows
  }

  // MARK: - Building

  private func build() async {
    buildShell()
    buildWindow()
    buildRug()
    buildCushions()
    buildCandles()
    buildBeads()
    await Task.yield()
    receiver = lighting.ambient(
      room, top: GenzColour(0xEAD0C0), bottom: GenzColour(0x6A4A48), exponent: 1.4)
    addLights()
    rigLights()
    lighting.apply(look)
    isBuilt = true
    room.isEnabled = isOnScreen
    screen.isLit = true
    placeCats()
    updateGlows()
    updateMarks()
  }

  private func buildShell() {
    let (width, height, wall) = (AdoptionLayout.width, AdoptionLayout.height, AdoptionLayout.wall)
    let window = AdoptionLayout.window
    let plaster = kit.matte(GenzColour(0x7A4E48))
    // The floor, wide and deep enough to walk off.
    room.addChild(
      kit.block(-3, -wall, -wall, width + 9, 12, wall, kit.matte(GenzColour(0x4A3028))))
    // The back wall, around the window's opening.
    room.addChild(kit.block(-3, -wall, 0, width + 6, wall, window.z0, plaster))
    room.addChild(kit.block(-3, -wall, window.z1, width + 6, wall, height - window.z1, plaster))
    room.addChild(
      kit.block(-3, -wall, window.z0, window.x0 + 3, wall, window.z1 - window.z0, plaster))
    room.addChild(
      kit.block(
        window.x1, -wall, window.z0, width + 3 - window.x1, wall, window.z1 - window.z0, plaster))
    // The skirting.
    room.addChild(kit.block(-3, 0, 0, width + 6, 0.06, 0.4, kit.matte(GenzColour(0xF0DCC0))))
  }

  private func buildWindow() {
    let window = AdoptionLayout.window
    room.addChild(
      kit.block(
        window.x0, -0.5, window.z0, window.x1 - window.x0, 0.05, window.z1 - window.z0,
        kit.glow(GenzColour(0x1C2342))))
    let moon = GenzRoomPoint(window.x1 - 0.7, -0.42, window.z1 - 0.8)
    room.addChild(
      kit.part(
        kit.prism(sides: 16, radius: 0.32, top: 0.32, height: 0.02),
        kit.glow(GenzColour(0xFFEFC8)), at: moon.scene,
        turn: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
    for (x, z) in [(2.5, 6.3), (3.1, 5.4), (3.7, 6.5), (2.8, 4.3), (4.4, 4.9)] as [(Float, Float)] {
      room.addChild(
        kit.part(
          kit.box([0.05, 0.05, 0.01]), kit.glow(GenzColour(0xFFF4DA)),
          at: GenzRoomPoint(x, -0.42, z).scene))
    }
    let frame = kit.matte(GenzColour(0xF0DCC0))
    let bar: Float = 0.2
    let span = window.x1 - window.x0
    let tall = window.z1 - window.z0
    room.addChild(kit.block(window.x0 - bar, -0.1, window.z1, span + bar * 2, 0.3, bar, frame))
    room.addChild(
      kit.block(window.x0 - bar, -0.1, window.z0 - bar, span + bar * 2, 0.5, bar, frame))
    room.addChild(kit.block(window.x0 - bar, -0.1, window.z0, bar, 0.3, tall, frame))
    room.addChild(kit.block(window.x1, -0.1, window.z0, bar, 0.3, tall, frame))
    let middle = (window.x0 + window.x1) / 2
    room.addChild(kit.block(middle - 0.06, -0.3, window.z0, 0.12, 0.1, tall, frame))
    room.addChild(
      kit.block(window.x0, -0.3, (window.z0 + window.z1) / 2 - 0.06, span, 0.1, 0.12, frame))
  }

  private func buildRug() {
    let rug = AdoptionLayout.rug
    room.addChild(
      kit.block(
        rug.x0, rug.y0, 0, rug.x1 - rug.x0, rug.y1 - rug.y0, 0.04,
        kit.matte(GenzColour(0xB5564E))))
    room.addChild(
      kit.block(
        rug.x0 + 0.3, rug.y0 + 0.3, 0.04, rug.x1 - rug.x0 - 0.6, rug.y1 - rug.y0 - 0.6, 0.01,
        kit.matte(GenzColour(0xE3B07A))))
    room.addChild(
      kit.block(
        rug.x0 + 0.45, rug.y0 + 0.45, 0.05, rug.x1 - rug.x0 - 0.9, rug.y1 - rug.y0 - 0.9, 0.01,
        kit.matte(GenzColour(0xC9685C))))
  }

  private func buildCushions() {
    let size = AdoptionLayout.cushion
    for (index, spot) in AdoptionLayout.cushions.enumerated() {
      let colour = Self.cushionColours[index % Self.cushionColours.count]
      let cushion = ModelEntity(
        mesh: .generateBox(
          size: [size.width, size.height, size.depth], cornerRadius: size.height * 0.45),
        materials: [kit.matte(GenzColour(colour))])
      cushion.position = GenzRoomPoint(spot.x, spot.y, size.height / 2 + 0.05).scene
      cushion.orientation = simd_quatf(angle: AdoptionLayout.heading(index), axis: [0, 1, 0])
      room.addChild(cushion)
      // A button in the middle.
      room.addChild(
        kit.part(
          kit.prism(sides: 10, radius: 0.07, top: 0.07, height: 0.03),
          kit.matte(GenzColour(0xF6E7D2)),
          at: GenzRoomPoint(spot.x, spot.y, size.height + 0.05).scene))
    }
  }

  private func buildCandles() {
    let wax = kit.matte(GenzColour(0xF6E7D2))
    for (index, spot) in AdoptionLayout.candles.enumerated() {
      let height: Float = index == 1 ? 0.45 : 0.7
      let base = spot.scene
      room.addChild(
        kit.part(kit.prism(sides: 12, radius: 0.16, top: 0.155, height: height), wax, at: base))
      room.addChild(
        kit.part(
          kit.prism(sides: 8, radius: 0.08, top: 0.0, height: 0.3), kit.glow(Self.flameColour),
          at: base + [0, height + 0.05, 0]))
      room.addChild(
        kit.part(
          kit.prism(sides: 8, radius: 0.045, top: 0.0, height: 0.17),
          kit.glow(GenzColour(0xFFF6E0)), at: base + [0, height + 0.07, 0.02]))
    }
  }

  private func buildBeads() {
    let materials = [kit.glow(Self.beadColour), kit.glow(GenzColour(0xFFC9A0))]
    for (index, bead) in AdoptionLayout.beads.enumerated() {
      room.addChild(
        kit.part(
          kit.prism(sides: 6, radius: 0.07, top: 0.05, height: 0.13), materials[index % 2],
          at: bead.scene))
    }
  }

  private func addLights() {
    room.addChild(
      lighting.key(
        Self.flameColour, intensity: 14_000, reach: 8, at: GenzRoomPoint(0.8, 5.8, 1.2)))
    room.addChild(
      lighting.key(
        Self.flameColour, intensity: 11_000, reach: 8, at: GenzRoomPoint(6.4, 5.8, 1.2)))
    room.addChild(
      lighting.key(
        GenzColour(0xFF9A52), intensity: 9_000, reach: 12, at: GenzRoomPoint(3.5, 7.5, 6.5)))
    room.addChild(
      lighting.key(Self.beadColour, intensity: 5_000, reach: 6, at: GenzRoomPoint(3.5, 1.0, 7)))
  }

  private func rigLights() {
    lighting.rim(
      at: GenzRoomPoint(3.5, 3, 0.8).scene, from: GenzRoomPoint(4.5, -1, 4).scene)
    lighting.core(at: GenzRoomPoint(3.5, 3.5, 3.5).scene)
    lighting.sun(at: GenzRoomPoint(3.5, 3, 0).scene, from: GenzRoomPoint(12, 6, 7).scene)
    for spot in AdoptionLayout.cushions {
      lighting.shadow(
        width: AdoptionLayout.cushion.width * 1.1, depth: AdoptionLayout.cushion.depth * 1.1,
        at: GenzRoomPoint(spot.x, spot.y, 0.06).scene)
    }
    room.addChild(lighting.root)
  }

  // MARK: - Cats

  private func placeCats() {
    let count = state.cats.count
    while holders.count < count {
      let index = holders.count
      let holder = Entity()
      holder.name = Self.catPrefix + String(index)
      let length = AdoptionLayout.catLength
      NookiDiorama.makeTappable(
        holder, size: [length * 0.8, length * 0.9, length * 0.8], center: [0, length * 0.4, 0])
      let seat = Entity()
      seat.name = Self.seatName
      holder.addChild(seat)
      lighting.shadow(width: length * 0.8, depth: length * 0.5, at: [0, 0.02, 0], in: holder)
      room.addChild(holder)
      holders.append(holder)
      rigs.append(nil)
      shown.append(nil)
      loads.append(nil)
    }
    for (index, holder) in holders.enumerated() { holder.isEnabled = index < count }
    if forward.count != count { forward = AdoptionLayout.forward(state) }
    if busyUntil.count != count { busyUntil = Array(repeating: 0, count: count) }
    placeHolders()
    for (index, choice) in state.cats.enumerated() where shown[index] != choice {
      loads[index]?.cancel()
      loads[index] = Task { [weak self] in
        guard let self, let (model, real) = await self.cats.cat(choice), !Task.isCancelled,
          index < self.state.cats.count, self.state.cats[index] == choice
        else { return }
        self.place(model, as: real, at: index)
        self.shown[index] = choice
      }
    }
  }

  private func place(_ model: Entity, as choice: CatChoice, at index: Int) {
    let bounds = model.visualBounds(relativeTo: nil)
    guard !bounds.isEmpty, bounds.extents.max().isFinite else {
      Self.log.error("An adoption cat has no size")
      return
    }
    let scale = AdoptionLayout.catLength / choice.model.anatomy.length
    model.scale = .one * scale
    model.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
    let rig = CatRig(
      model: model, clips: CatCatalog.clips(choice.model), anatomy: choice.model.anatomy)
    if let palette = CatCatalog.palette(choice.model, coat: choice.coat) { rig?.paint(palette) }
    guard let seat = holders[index].children.first(where: { $0.name == Self.seatName }) else {
      return
    }
    for child in Array(seat.children) { child.removeFromParent() }
    seat.addChild(model)
    if let receiver { NookiDiorama.visit(model) { $0.components.set(receiver) } }
    rig?.play(.sit, blend: 0)
    rigs[index] = rig
  }
}
