import CoreGraphics
import Foundation
import OSLog
import Pet
import PetScene
import RealityKit

/// The notes desk at night: blank paper under a desk lamp, pens and a mug, a cork board above with
/// the notes pinned (the latest large), and now and then the cat, sitting by the paper or asleep
/// on the desk. Built from the styled rooms' shared meshes; only the cat loads from a file.
@MainActor
final class DeskStage: RehearsedStage {
  static let notePrefix = "desk-note:"
  static let paperName = "desk-paper"
  static let catName = "desk-cat"

  let root = Entity()
  /// Whether a measuring run has been told this scene is drawing since it last came on screen.
  private var isAnnounced = false
  let screen = TabScreen()
  let deskScreen = DeskScreen()
  var onEvent: ((DeskSceneEvent) -> Void)?

  private let kit: GenzKit
  private let cats: GenzCatSource
  private let room = Entity()
  private let board = Entity()
  private let view: TabCamera
  private let frames = FrameClock()
  private var building: Task<Void, Never>?
  private(set) var isBuilt = false
  private var isOnScreen = false
  private var isRehearsing = false
  private var reduceMotion = false
  private var clock = 0.0
  private var receiver: ImageBasedLightReceiverComponent?
  private let lighting = TabLighting(coreShare: 0.3, boostLimit: 1.3, haloLimit: 1.1)
  private var look = LightingLook.off

  private var notes: [DeskNote] = []
  private var pinned: [DeskNote] = []
  private var noteMaterials: [UUID: (image: CGImage, material: UnlitMaterial)] = [:]
  private var lifts: [UUID: Double] = [:]
  private var holders: [UUID: Entity] = [:]
  private var beads: [GenzRoomPoint] = []
  /// The pencil lying on the paper, which fidgets now and then as if asking to be picked up.
  private let pencil = Entity()
  private var pencilRest = Transform()
  private var nextWiggle = 1.4
  private var paperGlow: Int?

  private let catHolder = Entity()
  /// The cat's soft shadow, there only while the cat is.
  private let catShadow = Entity()
  private var catChoice = CatChoice.standard
  private var shownCat: CatChoice?
  private var catLoad: Task<Void, Never>?
  private var rig: CatRig?
  private var visit = CatVisit(seed: UInt64.random(in: 1...UInt64.max))
  private var catOpacity: Float = 0
  private var petUntil: Double?

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "DeskStage")
  private static let lampColour = GenzColour(0xFFC36B)
  private static let ledColour = GenzColour(0xFFE2B0)
  private static let notePaper = GenzColour(0xFFF3E6)
  private static let liftLength = 0.3
  private static let tapDelay = Duration.milliseconds(260)

  init(kit: GenzKit, cats: GenzCatSource) {
    self.kit = kit
    self.cats = cats
    view = TabCamera(home: DeskLayout.camera)
    root.addChild(room)
    root.addChild(view.lens)
    room.isEnabled = false
  }

  // MARK: - Showing

  func show(_ state: DeskSceneState) {
    guard state.notes != notes else { return }
    notes = state.notes
    if isBuilt { pin() }
  }

  func setCat(_ choice: CatChoice) {
    guard choice != catChoice else { return }
    catChoice = choice
    if isBuilt { loadCat() }
  }

  func start() {
    if building == nil { building = Task { await build() } }
    frames.isPaused = !isOnScreen
    frames.run { [weak self] delta in self?.tick(delta) }
  }

  func setOnScreen(_ onScreen: Bool) {
    if !onScreen { isAnnounced = false }
    isOnScreen = onScreen
    room.isEnabled = (onScreen || isRehearsing) && isBuilt
    frames.isPaused = !onScreen
  }

  func setRehearsing(_ rehearsing: Bool) {
    isRehearsing = rehearsing
    if rehearsing, building == nil { building = Task { await build() } }
    room.isEnabled = (isOnScreen || rehearsing) && isBuilt
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
  }

  func orbit(byX deltaX: Float, y deltaY: Float) {
    view.orbit(byX: deltaX, y: deltaY)
    updateGlows()
  }

  func endOrbit(velocityX: Float, velocityY: Float) {
    view.release(animated: !reduceMotion)
  }

  func tap(_ entity: Entity) {
    if TabLook.named(Self.catName, from: entity) != nil, catOpacity > 0.5 {
      petCat()
      return
    }
    let event: DeskSceneEvent
    if let (_, raw) = TabLook.named(Self.notePrefix, from: entity), let id = UUID(uuidString: raw) {
      if !reduceMotion { lifts[id] = clock }
      event = .noteTapped(id)
    } else if TabLook.named(Self.paperName, from: entity) != nil {
      event = .paperTapped
    } else {
      return
    }
    Task {
      try? await Task.sleep(for: Self.tapDelay)
      onEvent?(event)
    }
  }

  // MARK: - Stepping

  private func tick(_ delta: TimeInterval) {
    clock += delta
    if ScenePerf.isOn, isBuilt, !isAnnounced {
      isAnnounced = true
      ScenePerf.shown(
        ScenePerf.Scene(
          name: "notes", orbit: { [weak self] in self?.orbit(byX: $0, y: $1) }, zoom: { _ in },
          release: { [weak self] in self?.endOrbit(velocityX: 0, velocityY: 0) },
          census: { [weak self] in self.map { SceneCensus.of($0.root) } ?? "" }))
    }
    lighting.step(delta)
    if view.step(Float(delta)) { updateGlows() }
    stepPaper()
    for (id, start) in lifts {
      let age = clock - start
      let lift = age < Self.liftLength ? Float(sin(age / Self.liftLength * .pi)) : 0
      holders[id]?.children.first?.position.z = 0.25 * lift
      if age >= Self.liftLength { lifts[id] = nil }
    }
    stepCat(delta)
  }

  private func stepCat(_ delta: TimeInterval) {
    guard let rig else { return }
    let stay = visit.step(delta)
    let wanted: Float = stay == .away ? 0 : 1
    if catOpacity != wanted {
      let rate = Float(delta) / (reduceMotion ? 0.01 : 0.6)
      catOpacity = wanted > catOpacity ? min(catOpacity + rate, 1) : max(catOpacity - rate, 0)
      catHolder.components.set(OpacityComponent(opacity: catOpacity))
      catHolder.isEnabled = catOpacity > 0
      catShadow.isEnabled = catOpacity > 0.5
    }
    if let petUntil {
      if clock < petUntil { return }
      self.petUntil = nil
    }
    switch stay {
    case .away: break
    case .napping: rig.play(.sleep)
    case .sitting:
      if let move = visit.takeFidget(), !reduceMotion {
        rig.play(move)
        petUntil = clock + (rig.duration(of: move).flatMap { $0.isFinite ? $0 : nil } ?? 2)
      } else if rig.current != .sit || !rig.isPlaying {
        rig.play(.sit)
      }
      rig.look(at: view.position, weight: 0.7)
    }
  }

  /// The paper breathes a soft glow, and the pencil on it rolls and lifts a little now and then.
  private func stepPaper() {
    guard !reduceMotion else { return }
    if let paperGlow, paperGlow < screen.glows.count {
      let breath = 0.5 - 0.5 * cos(clock * 2 * .pi / 2.6)
      screen.glows[paperGlow].strength = (0.2 + 0.22 * breath) * lighting.haloScale
    }
    let age = clock - nextWiggle
    if age > Self.wiggleLength {
      nextWiggle = clock + 2.6 + Double(abs(sin(clock * 7.3))) * 1.6
      pencil.transform = pencilRest
    } else if age >= 0 {
      let share = Float(age / Self.wiggleLength)
      let envelope = sin(share * .pi)
      var posed = pencilRest
      posed.translation.y += 0.07 * envelope
      posed.rotation =
        simd_quatf(angle: 0.12 * envelope * sin(share * .pi * 6), axis: [0, 1, 0]) * posed.rotation
      pencil.transform = posed
    }
  }

  private static let wiggleLength = 0.7

  private func petCat() {
    guard let rig else { return }
    visit.stayAWhile()
    rig.play(.happy)
    petUntil = clock + (rig.duration(of: .happy).flatMap { $0.isFinite ? $0 : nil } ?? 2.5)
  }

  private func updateGlows() {
    var glows: [TabGlow] = []
    let halos = lighting.haloScale
    let bulb = (DeskLayout.lamp.shade.scene) + [0, -0.1, 0]
    if let centre = view.project(bulb) {
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(3.2, at: bulb), colour: lighting.tint(Self.lampColour),
          strength: 0.5 * halos))
    }
    let paper = DeskLayout.paper.centre.scene
    paperGlow = nil
    if let centre = view.project(paper) {
      paperGlow = glows.count
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(2.6, at: paper),
          colour: lighting.tint(GenzColour(0xFFD9A0)), strength: 0.3 * halos))
    }
    let corners = DeskLayout.paperCorners.compactMap { view.project($0.scene) }
    deskScreen.paper = corners.count == 4 ? corners : []
    for bead in beads {
      let point = bead.scene
      guard let centre = view.project(point) else { continue }
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(0.42, at: point),
          colour: lighting.fairyColour ?? Self.ledColour, strength: 0.5 * halos))
    }
    screen.glows = glows
  }

  // MARK: - Building

  private func build() async {
    buildShell()
    buildDesk()
    buildBoard()
    buildPaper()
    buildLamp()
    buildThings()
    await Task.yield()
    receiver = lighting.ambient(
      room, top: GenzColour(0xEAD0C0), bottom: GenzColour(0x6A4A48), exponent: 1.4)
    addLights()
    rigLights()
    room.addChild(board)
    catHolder.name = Self.catName
    catHolder.position = DeskLayout.cat.spot.scene
    catHolder.orientation = simd_quatf(angle: DeskLayout.cat.heading, axis: [0, 1, 0])
    let length = DeskLayout.cat.length
    SceneParts.makeTappable(
      catHolder, size: [length * 0.8, length * 0.7, length * 0.8], center: [0, length * 0.3, 0])
    catHolder.isEnabled = false
    room.addChild(catHolder)
    lighting.apply(look)
    isBuilt = true
    room.isEnabled = isOnScreen || isRehearsing
    screen.isLit = true
    updateGlows()
    pin()
    loadCat()
  }

  private func buildShell() {
    let (width, height, wall) = (DeskLayout.width, DeskLayout.height, DeskLayout.wall)
    room.addChild(
      kit.block(-wall, -wall, -wall, width + wall * 2, 5, wall, kit.matte(GenzColour(0x3A2A24))))
    room.addChild(
      kit.block(-wall, -wall, 0, width + wall * 2, wall, height, kit.matte(GenzColour(0x6E4A44))))
    room.addChild(
      kit.block(
        -wall, -wall, height, width + wall * 2, wall + 0.06, 0.14,
        kit.matte(GenzColour(0xF0DCC0))))
    room.addChild(kit.block(0, 0, 0, width, 0.05, 1.0, kit.matte(GenzColour(0x5A3A36))))
  }

  private func buildDesk() {
    let desk = DeskLayout.desk
    let top = DeskLayout.deskTop
    let wood = kit.matte(GenzColour(0x8A5A3C))
    let face = kit.matte(GenzColour(0x9C6A48))
    let dark = kit.matte(GenzColour(0x5A3A28))
    let knob = kit.matte(GenzColour(0xD8B25A))
    room.addChild(
      kit.block(desk.x0, desk.y0, top - 0.16, desk.x1 - desk.x0, desk.y1 - desk.y0, 0.16, face))
    // Drawers on the left, legs on the right.
    room.addChild(
      kit.block(desk.x0 + 0.1, desk.y0 + 0.1, 0, 1.6, desk.y1 - desk.y0 - 0.2, top - 0.16, wood))
    for level in [Float(0.55), 1.4] {
      room.addChild(kit.block(desk.x0 + 0.2, desk.y1 - 0.08, level, 1.4, 0.04, 0.7, face))
      room.addChild(kit.block(desk.x0 + 0.8, desk.y1 - 0.06, level + 0.3, 0.2, 0.08, 0.08, knob))
    }
    for y in [desk.y0 + 0.15, desk.y1 - 0.3] {
      room.addChild(kit.block(desk.x1 - 0.3, y, 0, 0.15, 0.15, top - 0.16, dark))
    }
    room.addChild(
      kit.block(desk.x0 + 1.7, desk.y0 + 0.1, top - 0.5, desk.x1 - desk.x0 - 2.0, 0.08, 0.34, dark))
    // Anywhere on the desk top means drawing, so the first tap never misses the paper.
    let surface = Entity()
    surface.name = Self.paperName
    surface.position = GenzRoomPoint((desk.x0 + desk.x1) / 2, (desk.y0 + desk.y1) / 2, top).scene
    room.addChild(surface)
    SceneParts.makeTappable(
      surface, size: [desk.x1 - desk.x0, 0.3, desk.y1 - desk.y0], center: [0, 0.1, 0])
  }

  private func buildBoard() {
    let b = DeskLayout.board
    let frame = kit.matte(GenzColour(0x6B4632))
    let cork = kit.matte(GenzColour(0xB98A5A))
    let rim: Float = 0.14
    room.addChild(
      kit.block(b.x0, 0, b.z0, b.x1 - b.x0, DeskLayout.boardFront - 0.02, b.z1 - b.z0, cork))
    room.addChild(kit.block(b.x0 - rim, 0, b.z0 - rim, b.x1 - b.x0 + rim * 2, 0.24, rim, frame))
    room.addChild(kit.block(b.x0 - rim, 0, b.z1, b.x1 - b.x0 + rim * 2, 0.24, rim, frame))
    room.addChild(kit.block(b.x0 - rim, 0, b.z0, rim, 0.24, b.z1 - b.z0, frame))
    room.addChild(kit.block(b.x1, 0, b.z0, rim, 0.24, b.z1 - b.z0, frame))
    // Fairy lights looped along the top of the board.
    let count = 13
    let materials = [kit.glow(Self.ledColour), kit.glow(Self.lampColour)]
    beads = (0..<count).map { index in
      let t = Float(index) / Float(count - 1)
      return GenzRoomPoint(
        b.x0 - 0.2 + t * (b.x1 - b.x0 + 0.4), 0.3, b.z1 + 0.35 - 0.45 * sin(t * .pi))
    }
    for (index, bead) in beads.enumerated() {
      room.addChild(
        kit.part(
          kit.prism(sides: 6, radius: 0.07, top: 0.05, height: 0.13), materials[index % 2],
          at: bead.scene))
    }
  }

  private func buildPaper() {
    let spec = DeskLayout.paper
    let holder = Entity()
    holder.name = Self.paperName
    holder.position = spec.centre.scene
    holder.orientation = simd_quatf(angle: spec.yaw, axis: [0, 1, 0])
    // A few sheets, the top one blank, waiting for a drawing.
    let under = kit.matte(GenzColour(0xEADCC8))
    holder.addChild(
      kit.part(
        kit.box([spec.width, 0.02, spec.depth]), under, at: [0.06, 0.01, -0.04],
        turn: simd_quatf(angle: -0.07, axis: [0, 1, 0])))
    let top = kit.matte(GenzColour(0xFFF9F0))
    // A plane faces +z; laid flat it faces up, its top edge away from the viewer.
    holder.addChild(
      kit.part(
        kit.plane(width: spec.width, height: spec.depth), top, at: [0, 0.035, 0],
        turn: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])))
    // A pencil lying across the lower right of the page, ready to draw with.
    pencil.position = [spec.width * 0.08, 0.09, spec.depth * 0.3]
    pencil.orientation =
      simd_quatf(angle: .pi / 2 + 0.55, axis: [0, 1, 0])
      * simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
    pencilRest = pencil.transform
    pencil.addChild(
      kit.part(
        kit.prism(sides: 6, radius: 0.05, top: 0.05, height: 1.1), kit.matte(GenzColour(0xFFD166))))
    pencil.addChild(
      kit.part(
        kit.prism(sides: 6, radius: 0.05, top: 0.05, height: 0.12), kit.matte(GenzColour(0xF28A8A)),
        at: [0, -0.12, 0]))
    pencil.addChild(
      kit.part(
        kit.prism(sides: 6, radius: 0.05, top: 0.005, height: 0.18),
        kit.matte(GenzColour(0xE8C9A0)),
        at: [0, 1.1, 0]))
    holder.addChild(pencil)
    room.addChild(holder)
    SceneParts.makeTappable(
      holder, size: [spec.width + 0.4, 0.4, spec.depth + 0.6], center: [0, 0.1, 0.1])
  }

  private func buildLamp() {
    let lamp = DeskLayout.lamp
    let metal = kit.matte(GenzColour(0x3E5A52))
    let base = lamp.base.scene
    room.addChild(
      kit.part(kit.prism(sides: 10, radius: 0.36, top: 0.32, height: 0.1), metal, at: base))
    let elbow = GenzRoomPoint(lamp.base.x + 0.25, lamp.base.y + 0.25, lamp.shade.z + 0.7).scene
    let shadeTop = lamp.shade.scene + [0, 0.45, 0]
    for (from, to) in [(base + [0, 0.1, 0], elbow), (elbow, shadeTop)] {
      let length = simd_distance(from, to)
      room.addChild(
        kit.part(
          kit.box([0.08, 0.08, length]), metal, at: (from + to) / 2,
          turn: simd_quatf(from: [0, 0, 1], to: simd_normalize(to - from))))
    }
    room.addChild(
      kit.part(
        kit.prism(sides: 8, radius: 0.42, top: 0.12, height: 0.45), metal, at: lamp.shade.scene))
    room.addChild(
      kit.part(
        kit.prism(sides: 8, radius: 0.38, top: 0.38, height: 0.01), kit.glow(Self.ledColour),
        at: lamp.shade.scene + [0, -0.005, 0]))
    room.addChild(
      kit.part(
        kit.prism(sides: 8, radius: 0.12, top: 0.06, height: 0.14), kit.glow(GenzColour(0xFFF1D6)),
        at: lamp.shade.scene + [0, -0.12, 0]))
  }

  private func buildThings() {
    let top = DeskLayout.deskTop
    // A cup of pens at the back.
    let cup = GenzRoomPoint(4.95, 0.85, top)
    room.addChild(
      kit.part(
        kit.prism(sides: 10, radius: 0.26, top: 0.29, height: 0.55),
        kit.matte(GenzColour(0x4F6B8A)),
        at: cup.scene))
    for (index, colour) in [UInt32(0xE5503A), 0xFFD166, 0x7FB2FF].enumerated() {
      let lean = Float(index - 1) * 0.22
      room.addChild(
        kit.part(
          kit.box([0.06, 0.8, 0.06]), kit.matte(GenzColour(colour)),
          at: cup.scene + [Float(index - 1) * 0.1 + lean * 0.4, 0.55, Float(index % 2) * 0.06],
          turn: simd_quatf(angle: -lean, axis: [0, 0, 1])))
    }
    // A mug at the front right.
    let mug = GenzRoomPoint(5.2, 3.05, top).scene
    room.addChild(
      kit.part(
        kit.prism(sides: 12, radius: 0.22, top: 0.22, height: 0.42),
        kit.matte(GenzColour(0xF0DCC0)), at: mug))
    room.addChild(
      kit.part(
        kit.prism(sides: 12, radius: 0.19, top: 0.19, height: 0.01),
        kit.matte(GenzColour(0x5A3A2C)),
        at: mug + [0, 0.39, 0]))
    room.addChild(
      kit.part(
        kit.box([0.08, 0.22, 0.16]), kit.matte(GenzColour(0xF0DCC0)), at: mug + [0.26, 0.22, 0]))
    // Sticky notes, books and a small succulent.
    room.addChild(kit.block(1.0, 3.0, top, 0.5, 0.45, 0.12, kit.matte(GenzColour(0xFFD166))))
    let books = kit.build(GenzPiece(.bookStack))
    let size = GenzPiece.Kind.bookStack.size
    let stack = Entity()
    stack.position = GenzRoomPoint(1.0, 2.05, top).scene
    stack.orientation = simd_quatf(angle: 0.35, axis: [0, 1, 0])
    stack.scale = .one * 1.6
    books.position = GenzRoomPoint(-size.x / 2, -size.y / 2, 0).scene
    stack.addChild(books)
    room.addChild(stack)
    let pot = GenzRoomPoint(3.85, 0.75, top).scene
    room.addChild(
      kit.part(
        kit.prism(sides: 8, radius: 0.2, top: 0.25, height: 0.3), kit.matte(GenzColour(0xB97A55)),
        at: pot))
    for index in 0..<4 {
      let angle = Float(index) * .pi / 2 + 0.3
      room.addChild(
        kit.part(
          kit.prism(sides: 5, radius: 0.1, top: 0.01, height: 0.34),
          kit.matte(GenzColour(0x5E8C6A)),
          at: pot + [0.06 * cos(angle), 0.26, 0.06 * sin(angle)],
          turn: simd_quatf(angle: 0.35, axis: [sin(angle), 0, -cos(angle)])))
    }
  }

  private func addLights() {
    room.addChild(
      lighting.key(
        Self.lampColour, intensity: 18_000, reach: 7,
        at: GenzRoomPoint(
          DeskLayout.lamp.shade.x, DeskLayout.lamp.shade.y, DeskLayout.lamp.shade.z - 0.3)))
    room.addChild(
      lighting.key(
        GenzColour(0xFF9A52), intensity: 9_000, reach: 10, at: GenzRoomPoint(3, 5.5, 7.5)))
    room.addChild(
      lighting.key(Self.ledColour, intensity: 5_000, reach: 5, at: GenzRoomPoint(3, 1.2, 9.6)))
  }

  /// The preset's rig: a rim behind the cat's spot, a core light over the desk, a low sun from
  /// the side, and soft shadows under the desk, the lamp and the cat.
  private func rigLights() {
    let spot = DeskLayout.cat.spot
    lighting.rim(
      at: GenzRoomPoint(spot.x, spot.y, spot.z + 0.5).scene,
      from: GenzRoomPoint(spot.x + 0.8, spot.y - 1.6, spot.z + 3).scene)
    lighting.core(at: GenzRoomPoint(3, 3.2, 4).scene)
    lighting.sun(
      at: GenzRoomPoint(3, 2, DeskLayout.deskTop).scene, from: GenzRoomPoint(12, 6, 7).scene)
    let desk = DeskLayout.desk
    lighting.shadow(
      width: (desk.x1 - desk.x0) * 1.1, depth: (desk.y1 - desk.y0) * 1.25,
      at: GenzRoomPoint((desk.x0 + desk.x1) / 2, (desk.y0 + desk.y1) / 2, 0.012).scene)
    let base = DeskLayout.lamp.base
    lighting.shadow(
      width: 0.9, depth: 0.7, at: GenzRoomPoint(base.x, base.y, base.z + 0.012).scene)
    catShadow.position = GenzRoomPoint(spot.x, spot.y, spot.z + 0.012).scene
    catShadow.orientation = simd_quatf(angle: DeskLayout.cat.heading, axis: [0, 1, 0])
    catShadow.isEnabled = false
    room.addChild(catShadow)
    let length = DeskLayout.cat.length
    lighting.shadow(width: length * 0.9, depth: length * 0.6, at: .zero, in: catShadow)
    room.addChild(lighting.root)
  }

  // MARK: - Notes

  private func pin() {
    let wanted = Array(notes.prefix(DeskLayout.capacity))
    guard wanted != pinned else { return }
    pinned = wanted
    for child in Array(board.children) { child.removeFromParent() }
    holders = [:]
    let byID = Dictionary(wanted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for spot in DeskLayout.pins(for: wanted.map(\.id)) {
      guard let note = byID[spot.id], let material = material(for: note, large: spot.side > 1.5)
      else { continue }
      let holder = Entity()
      holder.name = Self.notePrefix + note.id.uuidString
      holder.position = spot.centre.scene
      holder.orientation = simd_quatf(angle: spot.tilt, axis: [0, 0, 1])
      let sheet = Entity()
      sheet.addChild(
        kit.part(kit.box([spot.side, spot.side, 0.02]), material, at: [0, 0, 0.01]))
      if spot.side < 1.5 {
        sheet.addChild(
          kit.part(
            kit.prism(sides: 8, radius: 0.07, top: 0.06, height: 0.07),
            kit.matte(GenzColour(DeskLayout.pinColours[spot.pin])),
            at: [0, spot.side / 2 - 0.1, 0.02],
            turn: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
      }
      holder.addChild(sheet)
      board.addChild(holder)
      holders[note.id] = holder
      SceneParts.makeTappable(holder, size: [spot.side, spot.side, 0.3], center: [0, 0, 0.1])
    }
    let shown = Set(wanted.map(\.id))
    noteMaterials = noteMaterials.filter { shown.contains($0.key) }
    deskScreen.isEmpty = wanted.isEmpty
    if wanted.isEmpty { pinPlaceholder() }
  }

  /// With no notes yet, a blank card pinned where the first one will go, its edge dashed.
  private func pinPlaceholder() {
    let large = DeskLayout.large
    guard let image = DeskArt.placeholder(), let material = TabLook.picture(image) else { return }
    let holder = Entity()
    holder.name = Self.paperName
    holder.position = GenzRoomPoint(large.centre.x, DeskLayout.boardFront, large.centre.y).scene
    holder.orientation = simd_quatf(angle: -0.04, axis: [0, 0, 1])
    holder.addChild(
      kit.part(kit.box([large.side, large.side, 0.02]), material, at: [0, 0, 0.01]))
    holder.addChild(
      kit.part(
        kit.prism(sides: 8, radius: 0.09, top: 0.08, height: 0.08),
        kit.matte(GenzColour(DeskLayout.pinColours[0])), at: [0, large.side / 2 - 0.14, 0.03],
        turn: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
    board.addChild(holder)
    SceneParts.makeTappable(
      holder, size: [large.side, large.side, 0.3], center: [0, 0, 0.1])
  }

  private func material(for note: DeskNote, large: Bool) -> UnlitMaterial? {
    if let cached = noteMaterials[note.id], cached.image === note.image { return cached.material }
    guard
      let image = GenzTextures.note(
        drawing: note.image, paper: Self.notePaper, aspect: 1, corners: large,
        pixels: large ? 512 : 256),
      let material = TabLook.picture(image, tint: GenzColour(0xF4E6D4))
    else { return nil }
    noteMaterials[note.id] = (note.image, material)
    return material
  }

  // MARK: - Cat

  private func loadCat() {
    guard catChoice != shownCat else { return }
    let wanted = catChoice
    catLoad?.cancel()
    catLoad = Task {
      guard let (model, shown) = await cats.cat(wanted), !Task.isCancelled, wanted == catChoice
      else { return }
      place(cat: model, as: shown)
      shownCat = wanted
    }
  }

  private func place(cat model: Entity, as shown: CatChoice) {
    let bounds = model.visualBounds(relativeTo: nil)
    guard !bounds.isEmpty, bounds.extents.max().isFinite else {
      Self.log.error("The desk cat has no size")
      return
    }
    let scale = DeskLayout.cat.length / shown.model.anatomy.length
    model.scale = .one * scale
    model.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
    let rig = CatRig(
      model: model, clips: CatCatalog.clips(shown.model), anatomy: shown.model.anatomy)
    if let palette = CatCatalog.coatTexture(shown.model, coat: shown.coat) { rig?.paint(palette) }
    for child in Array(catHolder.children) { child.removeFromParent() }
    catHolder.addChild(model)
    if let receiver { SceneParts.visit(model) { $0.components.set(receiver) } }
    rig?.play(.sit, blend: 0)
    self.rig = rig
  }
}

/// When the cat is at the desk, and what it does there: it sits by the paper a while, sometimes
/// naps, and wanders off for a while before it comes back. It is there when the desk first opens.
struct CatVisit {
  enum Stay: Equatable {
    case sitting
    case napping
    case away
  }

  private(set) var stay = Stay.sitting
  private var left: Double
  private var fidgetIn: Double
  private var random: SplitMix

  static let fidgets: [CatAction] = [.look, .groom, .slowBlink, .tailFlick, .yawn]

  init(seed: UInt64) {
    random = SplitMix(seed: seed)
    left = 40
    fidgetIn = 6
  }

  /// Steps `delta` seconds on and returns where the cat is now.
  mutating func step(_ delta: Double) -> Stay {
    left -= delta
    fidgetIn -= delta
    guard left <= 0 else { return stay }
    switch stay {
    case .sitting:
      stay = random.unit() < 0.45 ? .napping : .away
      left = stay == .napping ? 30 + random.unit() * 40 : 20 + random.unit() * 30
    case .napping:
      stay = .sitting
      left = 25 + random.unit() * 30
    case .away:
      stay = .sitting
      left = 30 + random.unit() * 40
    }
    return stay
  }

  /// A small move to play now while sitting, or `nil`.
  mutating func takeFidget() -> CatAction? {
    guard stay == .sitting, fidgetIn <= 0 else { return nil }
    fidgetIn = 7 + random.unit() * 8
    return Self.fidgets[Int(random.unit() * Double(Self.fidgets.count)) % Self.fidgets.count]
  }

  /// Keeps the cat sitting a little longer, as after it is petted.
  mutating func stayAWhile() {
    if stay != .away {
      stay = .sitting
      left = max(left, 20)
    }
  }
}
