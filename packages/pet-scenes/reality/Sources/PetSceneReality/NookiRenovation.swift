import Foundation
import Pet
import RealityKit
import simd

/// Applies the room's layout to its entities: repainting surfaces, and picking up, moving, turning
/// and setting down furniture. Where pieces may stand is ``DecorPlan``'s to say, through a
/// ``DecorSession``; this keeps the room in step with it and saves each change.
@MainActor final class NookiRenovation {
  private static let paintLength: Float = 0.6
  /// New pieces go as near here as there is room: the open floor in front of the bed.
  static let openFloor = SIMD2<Float>(-0.1, 0.4)
  private static let placementPrefix = "placement:"

  private struct Fade {
    var surfaces: [ModelEntity]
    var from: SIMD3<Float>
    var to: SIMD3<Float>
    var progress: Float = 0
  }

  private let store: NookiLayoutStore
  let decor = DecorSession(
    plan: DecorPlan(
      minimum: NookiFloorPlan.floorMin, maximum: NookiFloorPlan.floorMax, grid: 0.05),
    liftHeight: 0.08, markerHeight: NookiRenovation.markerHeight)
  /// How high the decorate marker floats: over the rug (29 mm), so it shows on it rather than
  /// hiding under it.
  static let markerHeight: Float = 0.035

  private var walls: [ModelEntity] = []
  private var floor: ModelEntity?
  private var wallBase = SIMD3<Float>.zero
  private var floorBase = SIMD3<Float>.zero
  private var wallShown = SIMD3<Float>.zero
  private var floorShown = SIMD3<Float>.zero
  private var fades: [Fade] = []

  private(set) var layout: NookiLayout
  var isOn: Bool {
    get { decor.isOn }
    set { decor.isOn = newValue }
  }
  /// Told when a surface takes one of the free paints.
  var onPainted: ((RoomSurface) -> Void)?
  /// Told where a piece from the shop was set down, and how it is turned.
  var onPlacementMoved: ((RoomLayout.Placement.ID, DecorBox) -> Void)?

  init(store: NookiLayoutStore) {
    self.store = store
    layout = store.load()
    decor.buildMarker()
    decor.onMoved = { [weak self] name, piece, box in self?.moved(name, piece: piece, to: box) }
  }

  /// True while a piece is picked up.
  var isLifting: Bool { decor.selected != nil }
  /// True while something is fading, rising or settling.
  var isMoving: Bool { decor.isMoving || !fades.isEmpty }

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
    decor.addFixed("fixed \(decor.plan.fixed.count)", DecorBox(centre: centre, half: half))
  }

  /// Registers a movable piece standing at its original spot. `half` is its footprint before it
  /// is turned.
  func register(_ name: String, holder: Entity, half: SIMD2<Float>, isFlat: Bool = false) {
    decor.register(name, holder: holder, half: half, isFlat: isFlat)
  }

  /// Makes a piece from the shop movable. The shop's layout holds where it stands.
  func register(placement id: RoomLayout.Placement.ID, holder: Entity, half: SIMD2<Float>) {
    decor.register(Self.name(of: id), holder: holder, half: half, placement: id)
  }

  func unregister(placement id: RoomLayout.Placement.ID) {
    decor.unregister(Self.name(of: id))
  }

  /// Moves a piece from the shop to where the shop's layout now says, so the plan knows.
  func shopMoved(placement id: RoomLayout.Placement.ID, x: Float, z: Float, yaw: Float) {
    let name = Self.name(of: id)
    guard let half = decor.plan.pieces[name]?.half else { return }
    decor.place(name, at: DecorBox(centre: [x, z], half: half, yaw: yaw))
  }

  /// Where a new piece of `half` extent can stand, or nil if the floor is full.
  func openSpot(half: SIMD2<Float>) -> SIMD2<Float>? {
    decor.plan.openSpot(half: half, near: Self.openFloor)
  }

  static func name(of id: RoomLayout.Placement.ID) -> String {
    placementPrefix + id
  }

  /// Makes `entity` travel with the piece `name`.
  func attach(_ entity: Entity, to name: String) {
    guard let holder = decor.pieces[name]?.holder else { return }
    entity.setParent(holder, preservingWorldTransform: true)
  }

  /// Shows the stored layout at once. Call this when the room has finished loading.
  func applyStored() {
    for (name, piece) in decor.pieces where piece.placement == nil {
      decor.place(name, at: stored(name, home: piece.home))
    }
    wallShown = layout.wall?.rgb ?? wallBase
    floorShown = layout.floor?.rgb ?? floorBase
    for wall in walls { Self.tint(wall, wallShown) }
    if let floor { Self.tint(floor, floorShown) }
  }

  /// Where the stored layout puts `name`: its own spot, the grid cell an older layout kept, or home.
  private func stored(_ name: String, home: DecorBox) -> DecorBox {
    var box = home
    if let spot = layout.spots?[name] {
      box.centre = [spot.x, spot.z]
      box.yaw = spot.yaw
    } else if let cell = layout.pieces[name] {
      box.centre = NookiFloorPlan.centre(of: cell)
    }
    return box
  }

  private func moved(_ name: String, piece: DecorSession.Piece, to box: DecorBox) {
    if let id = piece.placement {
      onPlacementMoved?(id, box)
      return
    }
    layout.pieces[name] = nil
    var spots = layout.spots ?? [:]
    spots[name] =
      box == piece.home ? nil : NookiLayout.Spot(x: box.centre.x, z: box.centre.y, yaw: box.yaw)
    layout.spots = spots.isEmpty ? nil : spots
    store.save(layout)
  }

  // MARK: - Painting

  /// Paints what `entity` is, if it is a wall or the floor. Returns whether it was.
  @discardableResult
  func paint(_ entity: Entity, _ swatch: NookiSwatch, reduceMotion: Bool) -> Bool {
    guard isSurface(entity) else { return false }
    if let wall = entity as? ModelEntity, walls.contains(wall) {
      onPainted?(.wall)
      guard layout.wall != swatch else { return true }
      layout.wall = swatch
      fade(walls, from: wallShown, to: swatch.rgb, reduceMotion: reduceMotion)
      wallShown = swatch.rgb
    } else if let floor {
      onPainted?(.floor)
      guard layout.floor != swatch else { return true }
      layout.floor = swatch
      fade([floor], from: floorShown, to: swatch.rgb, reduceMotion: reduceMotion)
      floorShown = swatch.rgb
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

  func isSurface(_ entity: Entity) -> Bool {
    entity === floor || walls.contains { $0 === entity }
  }

  func isPiece(_ entity: Entity) -> Bool {
    decor.piece(containing: entity) != nil
  }

  /// Puts everything back as it first was.
  func reset(reduceMotion: Bool) {
    _ = decor.resetAll()
    layout = NookiLayout()
    store.save(layout)
    fade(walls, from: wallShown, to: wallBase, reduceMotion: reduceMotion)
    wallShown = wallBase
    if let floor { fade([floor], from: floorShown, to: floorBase, reduceMotion: reduceMotion) }
    floorShown = floorBase
  }

  // MARK: - Updates

  func step(_ delta: Float, reduceMotion: Bool) {
    decor.step(delta, reduceMotion: reduceMotion)
    stepFades(delta)
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
