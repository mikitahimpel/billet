import CoreGraphics
import DesignSystem
import Foundation
import OSLog
import Pet
import PetScene
import RealityKit

/// The shop at night: a warm little room cut open at the front, the keeper behind the counter,
/// furniture on the shelves, treats on the counter and paints on a table by the window. Built from
/// the styled rooms' shared meshes; only the keeper and the furniture load from files.
@MainActor
final class ShopStage: RehearsedStage {
  static let itemPrefix = "shop-item:"
  static let keeperName = "shop-keeper"

  let root = Entity()
  /// Whether a measuring run has been told this scene is drawing since it last came on screen.
  private var isAnnounced = false
  let screen = TabScreen()
  let shopScreen = ShopScreen()
  /// Called with the item tapped, a moment after the tap so its hop and the keeper's glance read.
  var onPick: ((ShopItem.ID) -> Void)?

  private let kit: GenzKit
  private let room = Entity()
  private let stock = Entity()
  private let view: TabCamera
  private let models: NookiShopModels
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

  private var items: [ShopItem] = []
  private var stocked: [ShopItem.ID] = []
  private var stocking: Task<Void, Never>?
  private var holders: [ShopItem.ID: Entity] = [:]
  private var slots: [ShopItem.ID: ShopLayout.Slot] = [:]
  private var hops: [ShopItem.ID: Double] = [:]
  private var owned: Set<ShopItem.ID> = []

  /// The item brought forward, and how far each item is from its place to the front, 0 to 1.
  private var focused: ShopItem.ID?
  private var forward: [ShopItem.ID: Float] = [:]
  private var forwardScale: [ShopItem.ID: Float] = [:]
  private var spin: Float = 0

  /// Glints to come, each on an item from a time on the clock, and when the next idle one is.
  private var glints: [(item: ShopItem.ID, at: Double)] = []
  private var nextGlint = 2.5
  private var random = SplitMix(seed: UInt64.random(in: 1...UInt64.max))

  private let parcel = Entity()
  private var parcelFlight: (from: SIMD3<Float>, start: Double)?

  private let keeperHolder = Entity()
  private var keeper: Shopkeeper?
  private var shownKeeper: Shopkeeper?
  private var keeperLoad: Task<Void, Never>?
  private var rig: KeeperRig?
  private var motion = KeeperMotion(seed: UInt64.random(in: 1...UInt64.max))
  private var purchases: Int?
  private var welcomeAt: Double?

  private var beads: [GenzRoomPoint] = []
  /// The window's opening as the camera sees it from its home place, which the view outside is
  /// laid out on.
  private var homeWindow: [CGPoint] = []

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "ShopStage")
  private static let pickDelay = Duration.milliseconds(180)
  private static let hopLength = 0.32
  private static let glintLength = 0.7
  private static let parcelSize: Float = 1.7
  private static let forwardLength: Float = 0.45
  /// Where an item floats when it is brought forward: in front of the counter, at eye height.
  static let front = GenzRoomPoint(3.3, 6.1, 2.3)
  /// How big an item is brought forward, across its longest side, in room units.
  static let frontSize: Float = 1.7
  private static let lampColour = GenzColour(0xFFC36B)
  private static let ledColour = GenzColour(0xFFE2B0)

  init(kit: GenzKit, models: NookiShopModels? = nil) {
    self.kit = kit
    self.models = models ?? NookiShopModels()
    view = TabCamera(home: ShopLayout.camera)
    root.addChild(room)
    root.addChild(view.lens)
    room.isEnabled = false
  }

  // MARK: - Showing

  func show(_ state: ShopSceneState) {
    if state.items != items {
      items = state.items
      if isBuilt { restock() }
    }
    if state.keeper != keeper {
      keeper = state.keeper
      if isBuilt { loadKeeper() }
    }
    if let purchases, state.purchases > purchases { handOver() }
    purchases = state.purchases
    if state.owned != owned {
      owned = state.owned
      updateTags()
    }
    if state.focused != focused { focus(state.focused) }
  }

  func start() {
    if building == nil { building = Task { await build() } }
    frames.isPaused = !isOnScreen
    frames.run { [weak self] delta in self?.tick(delta) }
  }

  func setOnScreen(_ onScreen: Bool) {
    if !onScreen { isAnnounced = false }
    if onScreen, !isOnScreen { welcomeAt = clock + 0.5 }
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
    updateTags()
  }

  func orbit(byX deltaX: Float, y deltaY: Float) {
    view.orbit(byX: deltaX, y: deltaY)
    updateGlows()
    updateTags()
  }

  func endOrbit(velocityX: Float, velocityY: Float) {
    view.release(animated: !reduceMotion)
  }

  func tap(_ entity: Entity) {
    if TabLook.named(Self.keeperName, from: entity) != nil {
      motion.wave()
      return
    }
    guard let (holder, id) = TabLook.named(Self.itemPrefix, from: entity) else { return }
    pick(id, holder: holder)
  }

  /// Picks `id`, from its item or its tag: it hops, the keeper looks at it, and the host hears.
  func pick(_ id: ShopItem.ID) {
    guard let holder = holders[id] else { return }
    pick(id, holder: holder)
  }

  private func pick(_ id: ShopItem.ID, holder: Entity) {
    if !reduceMotion, id != focused { hops[id] = clock }
    if let head = rig?.head {
      let offset = holder.position(relativeTo: nil) - head.position(relativeTo: nil)
      var aim = KeeperMotion.aim(at: offset)
      aim.x = min(max(aim.x, -1.2), 1.2)
      motion.glance(yaw: aim.x, pitch: min(max(aim.y, -0.5), 0.5))
    }
    Task {
      try? await Task.sleep(for: Self.pickDelay)
      onPick?(id)
    }
  }

  // MARK: - Stepping

  private func tick(_ delta: TimeInterval) {
    clock += delta
    if ScenePerf.isOn, isBuilt, !isAnnounced {
      isAnnounced = true
      ScenePerf.shown(
        ScenePerf.Scene(
          name: "shop", orbit: { [weak self] in self?.orbit(byX: $0, y: $1) }, zoom: { _ in },
          release: { [weak self] in self?.endOrbit(velocityX: 0, velocityY: 0) },
          census: { [weak self] in self.map { SceneCensus.of($0.root) } ?? "" }))
    }
    lighting.step(delta)
    if view.step(Float(delta)) {
      updateGlows()
      updateTags()
    }
    if let welcomeAt, clock >= welcomeAt, isBuilt {
      self.welcomeAt = nil
      welcome()
    }
    if let rig, let head = rig.head {
      let offset = view.position - head.position(relativeTo: nil)
      rig.apply(motion.step(delta, viewer: KeeperMotion.aim(at: offset), still: reduceMotion))
    }
    stepItems(delta)
    stepGlint()
    stepParcel()
  }

  /// Every item bobs a little where it stands, out of step with the others; the one brought
  /// forward floats to the front, grown, and turns slowly; a tapped one hops.
  private func stepItems(_ delta: TimeInterval) {
    let rate = reduceMotion ? 1 : Float(delta) / Self.forwardLength
    var moving = false
    for (id, holder) in holders {
      guard let slot = slots[id] else { continue }
      let wanted: Float = id == focused ? 1 : 0
      var amount = forward[id] ?? 0
      if amount != wanted {
        amount = wanted > amount ? min(amount + rate, 1) : max(amount - rate, 0)
        forward[id] = amount
        moving = true
      }
      let ease = amount * amount * (3 - 2 * amount)
      let phase = Double(slot.centre.x * 1.7 + slot.centre.z * 2.3)
      let bob: Float = reduceMotion ? 0 : 0.07 * Float(0.5 - 0.5 * cos(clock * 1.9 + phase))
      let home = slot.centre.scene + [0, bob, 0]
      holder.position = home + (Self.front.scene - home) * ease
      var size = 1 + ((forwardScale[id] ?? 1) - 1) * ease
      if let start = hops[id] {
        let age = clock - start
        size *= 1 + 0.16 * (age < Self.hopLength ? Float(sin(age / Self.hopLength * .pi)) : 0)
        if age >= Self.hopLength { hops[id] = nil }
      }
      holder.scale = .one * size
      let wobble: Float = reduceMotion ? 0 : 0.06 * Float(sin(clock * 1.3 + phase))
      // Brought forward it swings slowly from side to side, so a flat thing never shows its back.
      let swing = 0.55 * sin(spin)
      holder.orientation = simd_quatf(angle: wobble * (1 - ease) + swing * ease, axis: [0, 1, 0])
    }
    if focused != nil, !reduceMotion { spin += Float(delta) * 0.9 }
    if moving { updateGlows() }
  }

  private func stepGlint() {
    if glints.isEmpty, clock >= nextGlint, focused == nil, !stocked.isEmpty {
      glints.append((stocked[Int(random.next() % UInt64(stocked.count))], clock))
      nextGlint = clock + 1.6 + random.unit() * 1.8
    }
    glints.removeAll { clock - $0.at > Self.glintLength }
    guard let glint = glints.first(where: { clock >= $0.at }), let slot = slots[glint.item],
      let holder = holders[glint.item]
    else {
      if shopScreen.glint != nil { shopScreen.glint = nil }
      return
    }
    let top = holder.position(relativeTo: room) + [0, slot.box.y * 0.8, 0]
    guard let centre = view.project(top) else { return }
    shopScreen.glint = ShopGlint(
      centre: centre, size: max(view.reach(0.9, at: top), 22),
      phase: (clock - glint.at) / Self.glintLength)
  }

  /// The parcel appears in the keeper's paws over the front of the counter while it hands it
  /// over, then flies to you and fades.
  private func stepParcel() {
    if let progress = motion.handOverProgress, progress < 0.7, let rig,
      let paws = rig.paws(relativeTo: room)
    {
      parcel.isEnabled = true
      let grow = Float(min(progress / 0.2, 1))
      // Held out over the counter, just clear of its top, between the paws.
      let over = GenzRoomPoint(
        ShopLayout.keeper.x, ShopLayout.counter.y0 + 0.45,
        ShopLayout.counterTop + 0.36 * Self.parcelSize / 2 + 0.05
      ).scene
      parcel.position = SIMD3(paws.x, max(paws.y, over.y), over.z)
      parcel.scale = .one * Self.parcelSize * grow
      parcel.components.set(OpacityComponent(opacity: 1))
      parcelFlight = (parcel.position, clock)
      return
    }
    guard let flight = parcelFlight else {
      parcel.isEnabled = false
      return
    }
    let age = Float((clock - flight.start) / 0.55)
    guard age < 1 else {
      parcelFlight = nil
      parcel.isEnabled = false
      return
    }
    let camera = view.position - [0, 2, 0]
    parcel.position = flight.from + (camera - flight.from) * (age * age * 0.45)
    parcel.scale = .one * Self.parcelSize * (1 + age * 0.6)
    parcel.components.set(OpacityComponent(opacity: 1 - age))
  }

  /// The keeper bows hello and sweeps its arms to the shelves, while a glint runs over each side
  /// it shows: first the shelves on its left, then those on its right, then the counter.
  private func welcome() {
    motion.welcome()
    let start = clock + KeeperMotion.greetLength + 0.25
    let half = KeeperMotion.presentLength / 2
    let shelf = stocked.compactMap { id in slots[id].map { (id, $0) } }
    let right = shelf.filter { $0.1.stand == .shelf && $0.1.centre.x > ShopLayout.keeper.x }
    let left = shelf.filter { $0.1.stand == .shelf && $0.1.centre.x <= ShopLayout.keeper.x }
    let front = shelf.filter { $0.1.stand != .shelf }
    var queue: [(ShopItem.ID, Double)] = []
    for (group, at) in [(right, start), (left, start + half), (front, start + 2 * half - 0.2)] {
      for (index, entry) in group.sorted(by: { $0.1.centre.z > $1.1.centre.z }).enumerated() {
        queue.append((entry.0, at + Double(index) * 0.12))
      }
    }
    glints = queue.map { (item: $0.0, at: $0.1) }
    nextGlint = (queue.last?.1 ?? clock) + 3
  }

  private func handOver() {
    motion.handOver()
    parcelFlight = nil
  }

  private func focus(_ id: ShopItem.ID?) {
    focused = id
    shopScreen.showsTags = id == nil
    spin = 0
    if let id, let holder = holders[id], forwardScale[id] == nil {
      let bounds = holder.visualBounds(relativeTo: holder)
      if !bounds.isEmpty, bounds.extents.max() > 0 {
        let scale = Self.frontSize / bounds.extents.max() * holder.scale.x
        forwardScale[id] = min(max(scale, 1), 4)
      }
    }
    updateGlows()
  }

  /// Puts each item's tag at the front edge of its place, in the view's points.
  private func updateTags() {
    var tags: [ShopTag] = []
    // The paints and boards on the table stand too close for a tag each: one sign for them all.
    let table = items.filter { slots[$0.id]?.stand == .table }
    if let first = table.first {
      let edges = table.compactMap { slots[$0.id] }.map {
        GenzRoomPoint($0.centre.x, $0.centre.y + $0.box.z / 2 + 0.05, $0.centre.z - 0.08)
      }
      let middle = GenzRoomPoint(
        edges.map(\.x).reduce(0, +) / Float(edges.count), ShopLayout.table.y1 + 0.05,
        ShopLayout.tableTop - 0.08)
      if let centre = view.project(middle.scene) {
        let prices = table.map(\.price)
        let low = prices.min() ?? first.price
        let high = prices.max() ?? first.price
        tags.append(
          ShopTag(
            id: first.id, centre: CGPoint(x: centre.x, y: centre.y + 8),
            price: low == high ? "\(low)" : "\(low)–\(high)", owned: false))
      }
    }
    for item in items where slots[item.id]?.stand != .table {
      guard let slot = slots[item.id] else { continue }
      let edge = GenzRoomPoint(
        slot.centre.x, slot.centre.y + slot.box.z / 2 + 0.05, slot.centre.z - 0.08)
      guard let centre = view.project(edge.scene) else { continue }
      tags.append(
        ShopTag(
          id: item.id, centre: CGPoint(x: centre.x, y: centre.y + 8), price: "\(item.price)",
          owned: owned.contains(item.id)))
    }
    tags = Self.spread(tags, width: view.size.width)
    if tags != shopScreen.tags { shopScreen.tags = tags }
  }

  /// Tags moved apart where items stand close, each stepping down under the one it would cover,
  /// and kept inside the view.
  static func spread(_ tags: [ShopTag], width: CGFloat) -> [ShopTag] {
    let (across, down): (CGFloat, CGFloat) = (40, 21)
    var placed: [ShopTag] = []
    for var tag in tags.sorted(by: { ($0.centre.y, $0.centre.x) < ($1.centre.y, $1.centre.x) }) {
      tag.centre.x = min(max(tag.centre.x, across / 2 + 4), width - across / 2 - 4)
      while placed.contains(where: {
        abs($0.centre.x - tag.centre.x) < across && abs($0.centre.y - tag.centre.y) < down
      }) {
        tag.centre.y += down
      }
      placed.append(tag)
    }
    return placed
  }

  private func updateGlows() {
    var glows: [TabGlow] = []
    let halos = lighting.haloScale
    for lamp in ShopLayout.lamps {
      let bulb = GenzRoomPoint(lamp.x, lamp.y, lamp.z - 0.2).scene
      guard let centre = view.project(bulb) else { continue }
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(3.4, at: bulb), colour: lighting.tint(Self.lampColour),
          strength: 0.32 * halos))
    }
    let counter = GenzRoomPoint(
      ShopLayout.keeper.x, ShopLayout.counter.y0, ShopLayout.counterTop + 0.6
    ).scene
    if let centre = view.project(counter) {
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(5, at: counter),
          colour: lighting.tint(GenzColour(0xFF8A3D)), strength: 0.16 * halos))
    }
    for bead in beads {
      let point = bead.scene
      guard let centre = view.project(point) else { continue }
      glows.append(
        TabGlow(
          centre: centre, radius: view.reach(0.45, at: point),
          colour: lighting.fairyColour ?? Self.ledColour, strength: 0.5 * halos))
    }
    if let focused, let amount = forward[focused], amount > 0.01 {
      let point = Self.front.scene
      if let centre = view.project(point) {
        glows.append(
          TabGlow(
            centre: centre, radius: view.reach(2.6, at: point),
            colour: lighting.tint(GenzColour(0xFFC36B)), strength: 0.45 * Double(amount)))
      }
    }
    screen.glows = glows
    let window = ShopLayout.window
    let corners = [
      GenzRoomPoint(0, window.y0, window.z0), GenzRoomPoint(0, window.y1, window.z0),
      GenzRoomPoint(0, window.y1, window.z1), GenzRoomPoint(0, window.y0, window.z1),
    ].compactMap { view.project($0.scene) }
    screen.window = corners.count == 4 ? corners : []
    let home = [
      GenzRoomPoint(0, window.y0, window.z0), GenzRoomPoint(0, window.y1, window.z0),
      GenzRoomPoint(0, window.y1, window.z1), GenzRoomPoint(0, window.y0, window.z1),
    ].compactMap { view.projectFromHome($0.scene) }
    homeWindow = home.count == 4 ? home : []
  }

  /// What the shop window looks out on at `date`: the same view, weather and hour as the room's.
  func windowState(choice: WindowViewChoice, dayLight: PetSceneDayLight?, at date: Date)
    -> WindowViewState
  {
    WindowViewState(
      view: choice.view, weather: choice.shownWeather, hour: choice.shownHour(room: dayLight?.here),
      time: 30, now: date.timeIntervalSinceReferenceDate, window: screen.window,
      home: homeWindow.isEmpty ? screen.window : homeWindow, lampOn: true)
  }

  // MARK: - Building

  private func build() async {
    for part in shell() { room.addChild(part) }
    buildShelves()
    buildCounter()
    buildTable()
    buildLamps()
    buildDecor()
    await Task.yield()
    receiver = lighting.ambient(
      room, top: GenzColour(0xF0D2B4), bottom: GenzColour(0x7A4C3C), exponent: 1.5)
    addLights()
    rigLights()
    room.addChild(stock)
    keeperHolder.name = Self.keeperName
    keeperHolder.position = ShopLayout.keeper.scene
    room.addChild(keeperHolder)
    buildParcel()
    lighting.apply(look)
    isBuilt = true
    room.isEnabled = isOnScreen || isRehearsing
    screen.isLit = true
    updateGlows()
    restock()
    loadKeeper()
  }

  private func shell() -> [Entity] {
    let (width, depth, height, wall) = (
      ShopLayout.width, ShopLayout.depth, ShopLayout.height, ShopLayout.wall
    )
    let window = ShopLayout.window
    let back = kit.matte(GenzColour(0x8C4F3C))
    let side = kit.matte(GenzColour(0x7A4434))
    let wood = kit.matte(GenzColour(0xD9B48A))
    let cap = kit.matte(GenzColour(0xF0DCC0))
    var parts: [Entity] = [
      // The boards' tops are the floor; the slab stops a little under them to show in the seams.
      kit.block(
        -wall, -wall, -wall - 0.02, width + wall, depth + wall, wall,
        kit.matte(GenzColour(0x4A2E22))),
      planks(),
      kit.block(-wall, -wall, 0, width + wall, wall, height, back),
      kit.block(0, 0, 0, width, 0.06, 1.15, kit.matte(GenzColour(0x6A3A2C))),
      kit.block(0, 0, 1.15, width, 0.1, 0.08, kit.matte(GenzColour(0xB07A54))),
      kit.block(-wall, -wall, height, width + wall, wall + 0.06, 0.14, cap),
      kit.block(-wall, -wall, height, wall + 0.06, depth + wall, 0.14, cap),
      // The left wall, around the shop window.
      kit.block(-wall, 0, 0, wall, window.y0, height, side),
      kit.block(-wall, window.y1, 0, wall, depth - window.y1, height, side),
      kit.block(-wall, window.y0, 0, wall, window.y1 - window.y0, window.z0, side),
      kit.block(
        -wall, window.y0, window.z1, wall, window.y1 - window.y0, height - window.z1, side),
      // Its frame, a cross of glazing bars and a deep sill. The sill's top and the jambs' faces
      // stand a little proud of the wall, so no two share a plane.
      kit.block(
        -0.12, window.y0 - 0.1, window.z0 - 0.14, 0.42, window.y1 - window.y0 + 0.2, 0.16, wood),
      kit.block(-0.1, window.y0 - 0.1, window.z1, 0.14, window.y1 - window.y0 + 0.2, 0.12, wood),
      kit.block(-0.1, window.y0 - 0.1, window.z0, 0.14, 0.12, window.z1 - window.z0, wood),
      kit.block(-0.1, window.y1 - 0.02, window.z0, 0.14, 0.12, window.z1 - window.z0, wood),
      kit.block(
        -0.14, (window.y0 + window.y1) / 2 - 0.04, window.z0, 0.08, 0.08, window.z1 - window.z0,
        wood),
      kit.block(
        -0.14, window.y0, (window.z0 + window.z1) / 2 - 0.04, 0.08, window.y1 - window.y0, 0.08,
        wood),
    ]
    return parts
  }

  /// Floorboards in two tones, as two meshes.
  private func planks() -> Entity {
    let floor = Entity()
    let board: Float = 0.62
    var rows: [[(centre: SIMD3<Float>, size: SIMD3<Float>)]] = [[], []]
    var y: Float = 0
    var index = 0
    while y < ShopLayout.depth {
      let size = min(board, ShopLayout.depth - y)
      rows[index % 2].append(
        (
          GenzRoomPoint(ShopLayout.width / 2, y + size / 2, -0.01).scene,
          SIMD3(ShopLayout.width, 0.02, size - 0.03)
        ))
      y += board
      index += 1
    }
    floor.addChild(
      kit.part(kit.boxes("shop planks a", rows[0]), kit.matte(GenzColour(0x8A5A3C))))
    floor.addChild(
      kit.part(kit.boxes("shop planks b", rows[1]), kit.matte(GenzColour(0x7A4E34))))
    return floor
  }

  /// The street outside the window at blue hour: a picture on a plane behind the glass.

  private func buildShelves() {
    let body = kit.matte(GenzColour(0x6B4632))
    let board = kit.matte(GenzColour(0xA0704C))
    let line = kit.matte(GenzColour(0x4A2E22))
    let knob = kit.matte(GenzColour(0xD8B25A))
    let depth = ShopLayout.shelfDepth
    let width = ShopLayout.bayWidth
    let cupboard = ShopLayout.shelves.last.map { $0 - ShopLayout.board } ?? 1.5
    let top = (ShopLayout.shelves.first ?? 4) + ShopLayout.shelfGap - 0.3
    for x in ShopLayout.bays {
      room.addChild(kit.block(x, 0, 0, width, depth, cupboard, body))
      room.addChild(kit.block(x + width / 2 - 0.02, depth, 0.15, 0.04, 0.02, cupboard - 0.3, line))
      room.addChild(kit.block(x + width / 2 - 0.22, depth, cupboard / 2, 0.1, 0.06, 0.1, knob))
      room.addChild(kit.block(x + width / 2 + 0.12, depth, cupboard / 2, 0.1, 0.06, 0.1, knob))
      room.addChild(kit.block(x - 0.1, 0, 0, 0.1, depth, top, body))
      room.addChild(kit.block(x + width, 0, 0, 0.1, depth, top, body))
      room.addChild(kit.block(x - 0.1, 0, top, width + 0.2, depth + 0.05, 0.1, board))
      for level in ShopLayout.shelves {
        room.addChild(
          kit.block(x, 0, level - ShopLayout.board, width, depth, ShopLayout.board, board))
      }
    }
    // The shop's mark between the bays, over the keeper's head: a gold stamp on a dark disc.
    let mark = Entity()
    mark.position = GenzRoomPoint(ShopLayout.keeper.x, 0.06, 4.45).scene
    mark.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
    mark.addChild(kit.part(kit.prism(sides: 16, radius: 0.62, top: 0.62, height: 0.06), knob))
    mark.addChild(
      kit.part(
        kit.prism(sides: 16, radius: 0.52, top: 0.52, height: 0.04),
        kit.matte(GenzColour(0x4A2E22)),
        at: [0, 0.06, 0]))
    mark.addChild(
      kit.part(kit.prism(sides: 12, radius: 0.3, top: 0.3, height: 0.04), knob, at: [0, 0.1, 0]))
    room.addChild(mark)
  }

  private func buildCounter() {
    let counter = ShopLayout.counter
    let top = ShopLayout.counterTop
    let width = counter.x1 - counter.x0
    let depth = counter.y1 - counter.y0
    room.addChild(
      kit.block(counter.x0, counter.y0, 0, width, depth, top - 0.1, kit.matte(GenzColour(0x6B4632)))
    )
    room.addChild(
      kit.block(
        counter.x0 - 0.12, counter.y0 - 0.1, top - 0.1, width + 0.24, depth + 0.2, 0.1,
        kit.matte(GenzColour(0xB98A5E))))
    var slats: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    var x = counter.x0 + 0.2
    while x < counter.x1 - 0.1 {
      slats.append(
        (
          GenzRoomPoint(x, counter.y1 + 0.02, (top - 0.25) / 2 + 0.12).scene,
          SIMD3(0.12, top - 0.45, 0.04)
        ))
      x += 0.36
    }
    room.addChild(kit.part(kit.boxes("shop counter slats", slats), kit.matte(GenzColour(0x7E5238))))
    room.addChild(
      kit.block(counter.x0, counter.y1, 0, width, 0.06, 0.14, kit.matte(GenzColour(0x4A2E22))))

    // The till and the bell, on the keeper's right.
    let till = kit.matte(GenzColour(0x3E5A52))
    room.addChild(kit.block(4.55, 3.3, top, 0.75, 0.6, 0.36, till))
    room.addChild(
      kit.block(4.6, 3.35, top + 0.36, 0.65, 0.18, 0.3, kit.matte(GenzColour(0x2A2530))))
    room.addChild(
      kit.block(4.67, 3.53, top + 0.42, 0.5, 0.04, 0.18, kit.glow(GenzColour(0xFFD08A))))
    let gold = kit.matte(GenzColour(0xD8B25A))
    room.addChild(
      kit.part(
        kit.prism(sides: 10, radius: 0.2, top: 0.2, height: 0.03), gold,
        at: GenzRoomPoint(4.2, 3.8, top).scene))
    room.addChild(
      kit.part(
        kit.prism(sides: 10, radius: 0.16, top: 0.03, height: 0.16), gold,
        at: GenzRoomPoint(4.2, 3.8, top + 0.03).scene))
  }

  private func buildTable() {
    let table = ShopLayout.table
    let top = ShopLayout.tableTop
    let wood = kit.matte(GenzColour(0xB98A5E))
    let leg = kit.matte(GenzColour(0x6B4632))
    room.addChild(
      kit.block(
        table.x0, table.y0, top - 0.08, table.x1 - table.x0, table.y1 - table.y0, 0.08, wood))
    for (x, y) in [
      (table.x0 + 0.1, table.y0 + 0.1), (table.x1 - 0.2, table.y0 + 0.1),
      (table.x0 + 0.1, table.y1 - 0.2), (table.x1 - 0.2, table.y1 - 0.2),
    ] {
      room.addChild(kit.block(x, y, 0, 0.1, 0.1, top - 0.08, leg))
    }
  }

  private func buildLamps() {
    let shade = kit.matte(GenzColour(0x3E5A52))
    let cord = kit.matte(GenzColour(0x2A2026))
    for lamp in ShopLayout.lamps {
      room.addChild(
        kit.block(
          lamp.x - 0.015, lamp.y - 0.015, lamp.z + 0.3, 0.03, 0.03, ShopLayout.height - lamp.z, cord
        ))
      room.addChild(
        kit.part(kit.prism(sides: 8, radius: 0.5, top: 0.14, height: 0.42), shade, at: lamp.scene))
      room.addChild(
        kit.part(
          kit.prism(sides: 8, radius: 0.44, top: 0.44, height: 0.01), kit.glow(Self.ledColour),
          at: lamp.scene + [0, -0.005, 0]))
      room.addChild(
        kit.part(
          kit.prism(sides: 8, radius: 0.12, top: 0.06, height: 0.16),
          kit.glow(GenzColour(0xFFF1D6)),
          at: lamp.scene + [0, -0.14, 0]))
    }
    // A string of warm bulbs along the top of the back wall.
    let count = 17
    let materials = [kit.glow(Self.ledColour), kit.glow(Self.lampColour)]
    beads = (0..<count).map { index in
      let t = Float(index) / Float(count - 1)
      return GenzRoomPoint(
        0.3 + t * (ShopLayout.width - 0.6), 0.22, ShopLayout.height - 0.3 - 0.4 * sin(t * .pi))
    }
    for (index, bead) in beads.enumerated() {
      room.addChild(
        kit.part(
          kit.prism(sides: 6, radius: 0.07, top: 0.05, height: 0.13), materials[index % 2],
          at: bead.scene))
    }
  }

  private func buildDecor() {
    place(
      GenzPiece(.roundRug, slots: [GenzColour(0x7A3B30), GenzColour(0xB4553F)]),
      at: GenzRoomPoint(ShopLayout.keeper.x, 5.35, 0))
    place(GenzPiece(.snakePlant), at: GenzRoomPoint(6.5, 5.3, 0))
  }

  private func place(_ piece: GenzPiece, at centre: GenzRoomPoint, yaw: Float = 0) {
    let built = kit.build(piece)
    let size = piece.kind.size
    built.position = GenzRoomPoint(-size.x / 2, -size.y / 2, 0).scene
    let holder = Entity()
    holder.position = centre.scene
    holder.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    holder.addChild(built)
    room.addChild(holder)
  }

  private func addLights() {
    for lamp in ShopLayout.lamps {
      room.addChild(
        lighting.key(
          Self.lampColour, intensity: 16_000, reach: 7,
          at: GenzRoomPoint(lamp.x, lamp.y, lamp.z - 0.3)))
    }
    room.addChild(
      lighting.key(
        GenzColour(0xFF9A52), intensity: 12_000, reach: 11, at: GenzRoomPoint(4.2, 6.4, 3.6)))
    room.addChild(
      lighting.key(
        GenzColour(0xFFD9A8), intensity: 7_000, reach: 6, at: GenzRoomPoint(3.5, 1.4, 4.9)))
    let moon = Entity()
    moon.components.set(
      DirectionalLightComponent(color: GenzColour(0x8FA6D8).platformColour, intensity: 380))
    moon.look(
      at: GenzRoomPoint(4, 3, 1).scene, from: GenzRoomPoint(-8, 3.4, 6).scene, relativeTo: room)
    room.addChild(moon)
  }

  /// The preset's rig: a rim behind the keeper, a core light over the counter, a low sun through
  /// the shop window, and soft shadows under the counter, the shelves, the table and the keeper.
  private func rigLights() {
    let keeper = ShopLayout.keeper
    lighting.rim(
      at: GenzRoomPoint(keeper.x, keeper.y, keeper.z + ShopLayout.keeperHeight * 0.6).scene,
      from: GenzRoomPoint(keeper.x + 0.8, keeper.y - 1.9, keeper.z + 4.6).scene)
    lighting.core(at: GenzRoomPoint(3.5, 4.2, 2.4).scene)
    lighting.sun(
      at: GenzRoomPoint(3.5, 3.5, 0.5).scene, from: GenzRoomPoint(-8, 3.4, 3.2).scene)
    let counter = ShopLayout.counter
    lighting.shadow(
      width: (counter.x1 - counter.x0) * 1.15, depth: (counter.y1 - counter.y0) * 1.5,
      at: GenzRoomPoint((counter.x0 + counter.x1) / 2, (counter.y0 + counter.y1) / 2, 0.012)
        .scene)
    for bay in ShopLayout.bays {
      lighting.shadow(
        width: ShopLayout.bayWidth * 1.15, depth: ShopLayout.shelfDepth * 1.8,
        at: GenzRoomPoint(bay + ShopLayout.bayWidth / 2, ShopLayout.shelfDepth / 2, 0.012).scene)
    }
    let table = ShopLayout.table
    lighting.shadow(
      width: (table.x1 - table.x0) * 1.2, depth: (table.y1 - table.y0) * 1.3,
      at: GenzRoomPoint((table.x0 + table.x1) / 2, (table.y0 + table.y1) / 2, 0.012).scene)
    lighting.shadow(
      width: 1.6, depth: 1.2, at: GenzRoomPoint(keeper.x, keeper.y, keeper.z + 0.012).scene)
    room.addChild(lighting.root)
  }

  /// A little parcel in craft paper tied with a red ribbon, which the keeper hands over.
  private func buildParcel() {
    let paper = kit.matte(GenzColour(0xF2DDB8))
    let ribbon = kit.matte(GenzColour(0xD8392B))
    parcel.addChild(kit.part(kit.box([0.5, 0.36, 0.4]), paper))
    parcel.addChild(kit.part(kit.box([0.08, 0.37, 0.41]), ribbon))
    parcel.addChild(kit.part(kit.box([0.51, 0.37, 0.08]), ribbon))
    parcel.scale = .one * Self.parcelSize
    parcel.addChild(
      kit.part(
        kit.box([0.2, 0.08, 0.1]), ribbon, at: [-0.08, 0.21, 0],
        turn: simd_quatf(angle: 0.5, axis: [0, 0, 1])))
    parcel.addChild(
      kit.part(
        kit.box([0.2, 0.08, 0.1]), ribbon, at: [0.08, 0.21, 0],
        turn: simd_quatf(angle: -0.5, axis: [0, 0, 1])))
    if let receiver { SceneParts.visit(parcel) { $0.components.set(receiver) } }
    parcel.isEnabled = false
    room.addChild(parcel)
  }

  // MARK: - Stock

  private func restock() {
    guard items.map(\.id) != stocked else { return }
    stocked = items.map(\.id)
    stocking?.cancel()
    for child in Array(stock.children) { child.removeFromParent() }
    holders = [:]
    slots = [:]
    forward = [:]
    forwardScale = [:]
    let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var furniture: [(ShopItem, Entity, ShopLayout.Slot)] = []
    for slot in ShopLayout.slots(for: items) {
      guard let item = byID[slot.item] else { continue }
      let holder = Entity()
      holder.name = Self.itemPrefix + item.id
      holder.position = slot.centre.scene
      stock.addChild(holder)
      holders[item.id] = holder
      slots[item.id] = slot
      switch item.look {
      case .furniture: furniture.append((item, holder, slot))
      case .treat(let shape):
        holder.addChild(
          kit.part(
            kit.prism(sides: 12, radius: 0.26, top: 0.26, height: 0.04),
            kit.matte(GenzColour(0xF0DCC0))))
        let treat = NookiShopModels.treat(shape)
        fill(holder, with: treat, slot: slot, unitsPerMetre: 3.2, least: 0.42, lift: 0.04)
      case .material(let surface, let tone):
        fill(holder, with: sample(surface, tone.swatch), slot: slot, unitsPerMetre: 1, least: 0)
      }
    }
    updateTags()
    stocking = Task {
      for (item, holder, slot) in furniture {
        guard let model = await models.furniture(item), !Task.isCancelled else { continue }
        fill(holder, with: model, slot: slot, unitsPerMetre: 1.7, least: 0.5)
      }
    }
  }

  /// Puts `model`, standing on y = 0 in metres, into `holder` at the size its slot allows.
  private func fill(
    _ holder: Entity, with model: Entity, slot: ShopLayout.Slot, unitsPerMetre: Float,
    least: Float, lift: Float = 0
  ) {
    let content = Entity()
    content.addChild(model)
    var bounds = content.visualBounds(relativeTo: content)
    guard !bounds.isEmpty else { return }
    if slot.stand == .shelf, ShopLayout.liesFlat(bounds.extents) {
      // A rug or a print lying flat reads better stood up, leaning back on the wall.
      model.orientation = simd_quatf(angle: 1.35, axis: [1, 0, 0])
      bounds = content.visualBounds(relativeTo: content)
    }
    let scale = ShopLayout.scale(
      extents: bounds.extents, box: slot.box, unitsPerMetre: unitsPerMetre, least: least)
    content.scale = .one * scale
    content.position =
      SIMD3(-bounds.center.x, -bounds.min.y + lift / scale, -bounds.center.z) * scale
    holder.addChild(content)
    if let receiver { SceneParts.visit(holder) { $0.components.set(receiver) } }
    TabLook.makeTappable(holder, margin: 0.12)
  }

  /// A paint tin in a wall colour, or a little stack of boards in a floor colour, in metres.
  private func sample(_ surface: RoomSurface, _ swatch: Swatch) -> Entity {
    let colour = GenzColour(
      UInt32(swatch.red) << 16 | UInt32(swatch.green) << 8 | UInt32(swatch.blue))
    let sample = Entity()
    switch surface {
    case .wall:
      let tin = kit.matte(GenzColour(0xC8C0B8))
      sample.addChild(kit.part(kit.prism(sides: 10, radius: 0.09, top: 0.09, height: 0.16), tin))
      sample.addChild(
        kit.part(
          kit.prism(sides: 10, radius: 0.1, top: 0.1, height: 0.08), kit.matte(colour),
          at: [0, 0.04, 0]))
      sample.addChild(
        kit.part(
          kit.prism(sides: 10, radius: 0.105, top: 0.105, height: 0.012), kit.matte(colour),
          at: [0, 0.16, 0]))
      // A drip down the side.
      sample.addChild(
        kit.part(kit.box([0.02, 0.05, 0.01]), kit.matte(colour), at: [0.02, 0.135, 0.09]))
    case .floor:
      for index in 0..<3 {
        sample.addChild(
          kit.part(
            kit.box([0.22, 0.03, 0.15]), kit.matte(colour.shaded(-0.12 * Float(index % 2))),
            at: [0, 0.015 + 0.03 * Float(index), 0],
            turn: simd_quatf(angle: Float(index) * 0.25 - 0.25, axis: [0, 1, 0])))
      }
    }
    return sample
  }

  // MARK: - Keeper

  private func loadKeeper() {
    guard let keeper, keeper != shownKeeper else { return }
    keeperLoad?.cancel()
    keeperLoad = Task {
      guard let model = await KeeperRig.load(keeper), !Task.isCancelled, keeper == self.keeper
      else { return }
      place(keeper: model, as: keeper)
    }
  }

  private func place(keeper model: Entity, as keeper: Shopkeeper) {
    let bounds = model.visualBounds(relativeTo: nil)
    guard !bounds.isEmpty, bounds.extents.y > 0 else {
      Self.log.error("Keeper \(keeper.rawValue, privacy: .public) has no size")
      return
    }
    let scale = ShopLayout.keeperHeight / bounds.extents.y
    model.scale = .one * scale
    model.position = SIMD3(-bounds.center.x, -bounds.min.y, -bounds.center.z) * scale
    for child in Array(keeperHolder.children) { child.removeFromParent() }
    keeperHolder.addChild(model)
    if let receiver { SceneParts.visit(model) { $0.components.set(receiver) } }
    TabLook.makeTappable(keeperHolder, margin: 0)
    rig = KeeperRig(model: model)
    shownKeeper = keeper
    if isOnScreen, motion.gesture == nil { welcomeAt = clock + 0.3 }
  }
}
