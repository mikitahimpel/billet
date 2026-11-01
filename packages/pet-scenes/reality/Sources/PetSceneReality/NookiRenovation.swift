import Foundation
import Pet
import RealityKit
import simd

/// Applies the room's layout to its entities: repainting surfaces, and lifting, moving and setting
/// down furniture. The rules are in ``NookiFloorPlan``; this keeps the room in step with them and
/// saves each change.
@MainActor final class NookiRenovation {
  private static let liftHeight: Float = 0.08
  private static let liftRate: Float = 14
  private static let paintLength: Float = 0.6
  private static let landingLength: Float = 0.6
  /// New pieces go as near here as there is room: the open floor in front of the bed.
  private static let openFloor = SIMD2<Float>(-0.1, 0.4)

  private struct Fade {
    var surfaces: [ModelEntity]
    var from: SIMD3<Float>
    var to: SIMD3<Float>
    var progress: Float = 0
  }

  private let store: NookiLayoutStore
  private var plan = NookiFloorPlan()
  private var holders: [String: Entity] = [:]
  private var walls: [ModelEntity] = []
  private var floor: ModelEntity?
  private var wallBase = SIMD3<Float>.zero
  private var floorBase = SIMD3<Float>.zero
  private var wallShown = SIMD3<Float>.zero
  private var floorShown = SIMD3<Float>.zero
  private var fades: [Fade] = []
  private var landings: [String: Float] = [:]
  private var lifted: String?
  private var liftedAt: Float = 0

  private(set) var layout: NookiLayout
  var isOn = false
  /// Told when a surface takes one of the free paints.
  var onPainted: ((RoomSurface) -> Void)?
  /// Told where a piece from the shop was set down.
  var onPlacementMoved: ((RoomLayout.Placement.ID, SIMD3<Float>) -> Void)?

  init(store: NookiLayoutStore) {
    self.store = store
    layout = store.load()
  }

  var isLifting: Bool { lifted != nil }
  /// True while something is fading, rising or settling.
  var isMoving: Bool { lifted != nil || !fades.isEmpty || !landings.isEmpty }

  // MARK: - Setting up

  func setSurfaces(
    walls: [ModelEntity], floor: ModelEntity, wall: SIMD3<Float>, ground: SIMD3<Float>
  ) {
    self.walls = walls
    self.floor = floor
    wallBase = wall
    floorBase = ground
    wallShown = wall
    floorShown = ground
  }

  func addFixed(centre: SIMD2<Float>, half: SIMD2<Float>) {
    plan.fixed.append(NookiFloorPlan.Area(centre: centre, half: half))
  }

  /// Registers a movable piece standing at its original spot.
  func register(_ name: String, holder: Entity, half: SIMD2<Float>) {
    holders[name] = holder
    plan.homes[name] = NookiFloorPlan.Area(
      centre: SIMD2(holder.position.x, holder.position.z), half: half)
  }

  /// Makes a piece from the shop movable. The shop's layout holds where it stands.
  func register(placement id: RoomLayout.Placement.ID, holder: Entity, half: SIMD2<Float>) {
    register(Self.name(of: id), holder: holder, half: half)
  }

  func unregister(placement id: RoomLayout.Placement.ID) {
    let name = Self.name(of: id)
    if lifted == name { lifted = nil }
    holders[name] = nil
    plan.homes[name] = nil
    landings[name] = nil
  }

  /// Where a new piece of `half` extent can stand, or nil if the floor is full.
  func openSpot(half: SIMD2<Float>) -> SIMD2<Float>? {
    plan.openCell(half: half, near: Self.openFloor, in: layout).map(NookiFloorPlan.centre)
  }

  private static let placementPrefix = "placement:"

  private static func name(of id: RoomLayout.Placement.ID) -> String {
    placementPrefix + id
  }

  /// Makes `entity` travel with the piece `name`.
  func attach(_ entity: Entity, to name: String) {
    guard let holder = holders[name] else { return }
    entity.setParent(holder, preservingWorldTransform: true)
  }

  /// Shows the stored layout at once. Call this when the room has finished loading.
  func applyStored() {
    for name in holders.keys { standInPlace(name) }
    wallShown = layout.wall?.rgb ?? wallBase
    floorShown = layout.floor?.rgb ?? floorBase
    for wall in walls { Self.tint(wall, wallShown) }
    if let floor { Self.tint(floor, floorShown) }
  }

  // MARK: - Painting

  /// Paints what `entity` is, if it is a wall or the floor. Returns whether it was.
  @discardableResult
  func paint(_ entity: Entity, _ swatch: NookiSwatch, reduceMotion: Bool) -> Bool {
    if let wall = entity as? ModelEntity, walls.contains(wall) {
      layout.wall = swatch
      fade(walls, from: wallShown, to: swatch.rgb, reduceMotion: reduceMotion)
      wallShown = swatch.rgb
      onPainted?(.wall)
    } else if let floor, entity === floor {
      layout.floor = swatch
      fade([floor], from: floorShown, to: swatch.rgb, reduceMotion: reduceMotion)
      floorShown = swatch.rgb
      onPainted?(.floor)
    } else {
      return false
    }
    store.save(layout)
    return true
  }

  private func fade(
    _ surfaces: [ModelEntity], from: SIMD3<Float>, to: SIMD3<Float>, reduceMotion: Bool
  ) {
    fades.removeAll { $0.surfaces == surfaces }
    if reduceMotion {
      for surface in surfaces { Self.tint(surface, to) }
    } else {
      fades.append(Fade(surfaces: surfaces, from: from, to: to))
    }
  }

  // MARK: - Moving

  /// Picks up the piece `entity` belongs to. Returns whether there was one.
  func lift(_ entity: Entity) -> Bool {
    guard isOn, lifted == nil, let name = holders.first(where: { $0.value === entity })?.key else {
      return false
    }
    lifted = name
    liftedAt = 0
    landings[name] = nil
    return true
  }

  /// Follows the finger to the nearest free cell. A taken cell leaves the piece where it was.
  func move(towards point: SIMD2<Float>) {
    guard let lifted,
      let cell = plan.cell(for: lifted, nearest: point, in: layout)
    else { return }
    layout.pieces[lifted] = cell
    standInPlace(lifted)
  }

  /// Sets the piece down, and says where.
  func drop() -> SIMD3<Float>? {
    guard let lifted, let holder = holders[lifted] else { return nil }
    self.lifted = nil
    if lifted.hasPrefix(Self.placementPrefix) { settle(lifted, at: holder.position) }
    store.save(layout)
    landings[lifted] = 0
    return holder.position
  }

  /// A shop piece has no original spot to return to: where it lands becomes its home.
  private func settle(_ name: String, at position: SIMD3<Float>) {
    plan.homes[name]?.centre = SIMD2(position.x, position.z)
    layout.pieces[name] = nil
    onPlacementMoved?(String(name.dropFirst(Self.placementPrefix.count)), position)
  }

  /// Puts everything back as it first was.
  func reset(reduceMotion: Bool) {
    lifted = nil
    layout = NookiLayout()
    store.save(layout)
    for name in holders.keys {
      standInPlace(name)
      landings[name] = 0
    }
    fade(walls, from: wallShown, to: wallBase, reduceMotion: reduceMotion)
    wallShown = wallBase
    if let floor { fade([floor], from: floorShown, to: floorBase, reduceMotion: reduceMotion) }
    floorShown = floorBase
  }

  private func standInPlace(_ name: String) {
    guard let holder = holders[name], let area = plan.area(of: name, in: layout) else { return }
    holder.position.x = area.centre.x
    holder.position.z = area.centre.y
  }

  // MARK: - Updates

  func step(_ delta: Float, reduceMotion: Bool) {
    stepLift(delta, reduceMotion: reduceMotion)
    stepLandings(delta, reduceMotion: reduceMotion)
    stepFades(delta)
  }

  private func stepLift(_ delta: Float, reduceMotion: Bool) {
    guard let lifted, let holder = holders[lifted] else { return }
    let goal = reduceMotion ? 0 : Self.liftHeight
    liftedAt += (goal - liftedAt) * (1 - exp(-Self.liftRate * delta))
    holder.position.y = liftedAt
  }

  private func stepLandings(_ delta: Float, reduceMotion: Bool) {
    for (name, elapsed) in landings {
      guard let holder = holders[name] else { continue }
      let next = elapsed + delta
      let done = reduceMotion || next >= Self.landingLength
      holder.position.y = done ? 0 : Self.bounce(next)
      landings[name] = done ? nil : next
    }
  }

  /// Height of a piece settling after it lands: a small hop that dies away.
  static func bounce(_ elapsed: Float) -> Float {
    0.03 * exp(-6 * elapsed) * abs(cos(elapsed * 9))
  }

  private func stepFades(_ delta: Float) {
    for index in fades.indices {
      fades[index].progress = min(fades[index].progress + delta / Self.paintLength, 1)
      let fade = fades[index]
      let eased = fade.progress * fade.progress * (3 - 2 * fade.progress)
      for surface in fade.surfaces { Self.tint(surface, mix(fade.from, fade.to, t: eased)) }
    }
    fades.removeAll { $0.progress >= 1 }
  }

  private static func tint(_ surface: ModelEntity, _ rgb: SIMD3<Float>) {
    guard var material = surface.model?.materials.first as? PhysicallyBasedMaterial else { return }
    material.baseColor = .init(
      tint: Material.Color(
        red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1))
    surface.model?.materials = [material]
  }
}
