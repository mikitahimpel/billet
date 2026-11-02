import DesignSystem
import Foundation
import Pet
import RealityKit

/// What the shop has put into the Nooki room: bought furniture, painted surfaces, and a treat
/// falling into the bowl. It owns its own entities beside the diorama's, so the diorama does not
/// know the shop exists.
@MainActor
final class NookiShopRoom {
  let root = Entity()

  private let models: NookiShopModels
  private let catalog: ShopCatalog
  private let renovation: NookiRenovation?
  private var pieces: [RoomLayout.Placement.ID: Entity] = [:]
  private var loading: [RoomLayout.Placement.ID: Task<Void, Never>] = [:]
  private var surfaces: [RoomSurface: ModelEntity] = [:]
  private var painted: [RoomSurface: ShopItem.ID] = [:]
  /// The room's ambient light. Without it the shop's entities take only direct light and look
  /// far darker than the same colour on the diorama.
  var ambient: ImageBasedLightReceiverComponent? {
    didSet { light(root) }
  }

  private static let bowl: SIMD3<Float> = [0.12, 0.04, 0.6]
  private static let fall: Float = 0.5
  static let fallDuration: TimeInterval = 0.55

  init(
    catalog: ShopCatalog = .standard,
    models: NookiShopModels = NookiShopModels(),
    renovation: NookiRenovation? = nil
  ) {
    self.catalog = catalog
    self.models = models
    self.renovation = renovation
  }

  /// The floor a piece of `item` needs, before its model has loaded.
  static func footprint(of item: ShopItem) -> SIMD2<Float> {
    guard case .furniture(_, let fit, let size, _) = item.look else { return .zero }
    let half = Float(size) / 2
    return .one * (fit == .width ? half : min(half, maximumHalfWidth))
  }

  /// A piece fitted by height can be tall and narrow, so its height says little about its width.
  private static let maximumHalfWidth: Float = 0.2

  private func light(_ entity: Entity) {
    guard let ambient else { return }
    NookiDiorama.visit(entity) { $0.components.set(ambient) }
  }

  /// Brings the room in line with `layout`: new pieces appear, removed ones go, surfaces recolour.
  func apply(_ layout: RoomLayout) {
    for surface in RoomSurface.allCases { paint(surface, with: layout.material(on: surface)) }
    let wanted = Set(layout.placements.map(\.id))
    for id in Array(pieces.keys) where !wanted.contains(id) {
      pieces.removeValue(forKey: id)?.removeFromParent()
      renovation?.unregister(placement: id)
    }
    for id in Array(loading.keys) where !wanted.contains(id) {
      loading.removeValue(forKey: id)?.cancel()
    }
    for placement in layout.placements {
      if let piece = pieces[placement.id] {
        position(piece, for: placement)
      } else if loading[placement.id] == nil {
        loading[placement.id] = Task { await add(placement) }
      }
    }
  }

  private func add(_ placement: RoomLayout.Placement) async {
    defer { loading[placement.id] = nil }
    guard let item = catalog.item(placement.item), let entity = await models.furniture(item),
      !Task.isCancelled
    else { return }
    let holder = Entity()
    holder.addChild(entity)
    let isOnWall: Bool
    if case .furniture(_, _, _, .wall) = item.look { isOnWall = true } else { isOnWall = false }
    if isOnWall { holder.name = "wall" }
    position(holder, for: placement, item: item)
    pieces[placement.id] = holder
    root.addChild(holder)
    light(holder)
    guard !isOnWall else { return }
    let bounds = entity.visualBounds(relativeTo: holder)
    NookiDiorama.makeTappable(holder, size: bounds.extents, center: bounds.center)
    renovation?.register(
      placement: placement.id, holder: holder,
      half: SIMD2(bounds.extents.x, bounds.extents.z) / 2)
  }

  private func position(
    _ holder: Entity, for placement: RoomLayout.Placement, item: ShopItem? = nil
  ) {
    let item = item ?? catalog.item(placement.item)
    var height: Float = 0
    if let item, case .furniture(_, _, _, .wall) = item.look { height = 0.46 }
    holder.position = [Float(placement.x), height, Float(placement.z)]
    holder.orientation = simd_quatf(angle: Float(placement.yaw), axis: [0, 1, 0])
  }

  // MARK: Surfaces

  /// Thin slabs laid just proud of the walls and floor, which stay as the diorama built them.
  private static let slabs: [RoomSurface: (size: SIMD3<Float>, centre: SIMD3<Float>)] = [
    .floor: ([1.3, 0.0015, 1.3], [0.05, 0.00075, 0.05])
  ]
  private static let wallSlabs: [(size: SIMD3<Float>, centre: SIMD3<Float>)] = [
    ([1.3, 0.86, 0.0015], [0.05, 0.43, -0.59925]),
    ([0.0015, 0.86, 1.3], [-0.59925, 0.43, 0.05]),
  ]

  private func paint(_ surface: RoomSurface, with id: ShopItem.ID?) {
    guard painted[surface] != id else { return }
    painted[surface] = id
    guard let id, let item = catalog.item(id), case .material(_, let tone) = item.look else {
      surfaces[surface]?.isEnabled = false
      return
    }
    let material = NookiShopModels.material(tone.swatch)
    if let slab = surfaces[surface] {
      for child in slab.children.compactMap({ $0 as? ModelEntity }) {
        child.model?.materials = [material]
      }
      slab.isEnabled = true
      return
    }
    let slab = ModelEntity()
    let shapes = surface == .floor ? [Self.slabs[.floor]!] : Self.wallSlabs
    for shape in shapes {
      let part = ModelEntity(mesh: .generateBox(size: shape.size), materials: [material])
      part.position = shape.centre
      slab.addChild(part)
    }
    surfaces[surface] = slab
    root.addChild(slab)
    light(slab)
  }

  // MARK: Treats

  /// Drops `treat` into the bowl, then clears it away.
  func drop(_ treat: ShopItem.ID?) {
    guard let treat, let item = catalog.item(treat), case .treat(let shape) = item.look else {
      return
    }
    let entity = NookiShopModels.treat(shape)
    entity.position = Self.bowl + [0, Self.fall, 0]
    root.addChild(entity)
    light(entity)
    var landing = entity.transform
    landing.translation = Self.bowl
    entity.move(to: landing, relativeTo: root, duration: Self.fallDuration, timingFunction: .easeIn)
    Task {
      try? await Task.sleep(for: .seconds(Self.fallDuration + 0.6))
      entity.removeFromParent()
    }
  }
}
