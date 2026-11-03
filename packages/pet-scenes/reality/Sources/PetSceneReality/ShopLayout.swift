import Foundation
import Pet
import simd

/// Where everything stands in the shop, in room units (``GenzRoomPoint``): two bays of shelves on
/// the back wall with the furniture, the treats in a row on the counter, and the paints and floor
/// samples on a low table by the window. The keeper stands between the bays, behind the counter.
enum ShopLayout {
  static let width: Float = 7
  static let depth: Float = 7
  static let height: Float = 5.6
  static let wall: Float = 0.3

  /// The left edge of each bay of shelves, and how wide a bay is.
  static let bays: [Float] = [0.35, 4.45]
  static let bayWidth: Float = 2.2
  static let shelfDepth: Float = 0.95
  /// The top of each shelf board, from the highest down.
  static let shelves: [Float] = [3.95, 2.8, 1.65]
  static let shelfGap: Float = 1.15
  static let board: Float = 0.08

  static let counter = (x0: Float(1.55), x1: Float(5.45), y0: Float(3.15), y1: Float(4.15))
  static let counterTop: Float = 1.6
  static let table = (x0: Float(0.3), x1: Float(2.4), y0: Float(4.55), y1: Float(5.75))
  static let tableTop: Float = 0.95
  /// The shop window in the left wall: from `y0` to `y1` along it, `z0` to `z1` up.
  static let window = (y0: Float(1.4), y1: Float(5.4), z0: Float(1.5), z1: Float(4.4))

  static let keeper = GenzRoomPoint(3.5, 2.15, 0.2)
  /// How tall the keeper stands, ears and all, in room units.
  static let keeperHeight: Float = 3.5
  /// The two lamps over the counter.
  static let lamps = [GenzRoomPoint(2.4, 3.65, 4.55), GenzRoomPoint(4.6, 3.65, 4.55)]

  static let camera = GenzCamera.Home(
    target: GenzRoomPoint(3.6, 3.2, 2.5).scene, yaw: 0.34, pitch: 0.3, distance: 25.5,
    fieldOfView: 40, yawLimits: 0.1...0.62, pitchLimits: 0.18...0.5)

  /// A place for one item: where it stands, the box it must fit in (scene axes: across, up,
  /// deep) and what sort of stand it is on.
  struct Slot: Equatable {
    enum Stand: Equatable {
      case shelf
      case counter
      case table
    }

    var item: ShopItem.ID
    /// The middle of the item's footprint, on the surface it stands on.
    var centre: GenzRoomPoint
    var box: SIMD3<Float>
    var stand: Stand
  }

  /// A place for every item, in catalog order within each kind. Furniture fills the shelves from
  /// the top of the left bay; a long catalog puts more to a shelf, up to three.
  static func slots(for items: [ShopItem]) -> [Slot] {
    var slots: [Slot] = []
    let furniture = items.filter { $0.category == .furniture }
    let shelfCount = bays.count * shelves.count
    let perShelf = min(max(2, (furniture.count + shelfCount - 1) / shelfCount), 3)
    let placeWidth = bayWidth / Float(perShelf)
    for (index, item) in furniture.prefix(shelfCount * perShelf).enumerated() {
      let shelf = index / perShelf
      let bay = shelf / shelves.count
      let level = shelf % shelves.count
      let place = index % perShelf
      slots.append(
        Slot(
          item: item.id,
          centre: GenzRoomPoint(
            bays[bay] + placeWidth * (Float(place) + 0.5), shelfDepth / 2 + 0.05,
            shelves[level]),
          box: [placeWidth - 0.18, shelfGap - 0.22, shelfDepth - 0.15], stand: .shelf))
    }

    let treats = items.filter { $0.category == .treats }
    for (index, item) in treats.prefix(4).enumerated() {
      slots.append(
        Slot(
          item: item.id,
          centre: GenzRoomPoint(
            counter.x0 + 0.45 + 0.52 * Float(index), (counter.y0 + counter.y1) / 2, counterTop),
          box: [0.48, 0.5, 0.48], stand: .counter))
    }

    let materials = items.filter { $0.category == .materials }
    let walls = materials.filter { surface(of: $0) == .wall }
    let floors = materials.filter { surface(of: $0) == .floor }
    let tableWidth = table.x1 - table.x0
    for (row, group) in [walls, floors].enumerated() {
      let shown = group.prefix(5)
      let step = tableWidth / Float(max(shown.count, 1))
      for (index, item) in shown.enumerated() {
        slots.append(
          Slot(
            item: item.id,
            centre: GenzRoomPoint(
              table.x0 + step * (Float(index) + 0.5),
              table.y0 + 0.35 + 0.55 * Float(row), tableTop),
            box: [step - 0.1, 0.6, 0.45], stand: .table))
      }
    }
    return slots
  }

  static func surface(of item: ShopItem) -> RoomSurface? {
    switch item.look {
    case .material(let surface, _): surface
    case .furniture, .treat: nil
    }
  }

  /// The scale that shows a model of `extents` (in metres, scene axes) in `box`: true to life at
  /// `unitsPerMetre`, but never smaller than `least` across its longest side, and never larger
  /// than the box.
  static func scale(
    extents: SIMD3<Float>, box: SIMD3<Float>, unitsPerMetre: Float, least: Float
  ) -> Float {
    let longest = extents.max()
    guard longest > 0 else { return 1 }
    let fit = (box / simd_max(extents, SIMD3(repeating: 0.0001))).min()
    return min(fit, max(unitsPerMetre, least / longest))
  }

  /// Whether a model of `extents` lies flat, like a rug, so it is better stood up to face the
  /// shop than laid on the shelf.
  static func liesFlat(_ extents: SIMD3<Float>) -> Bool {
    extents.y < 0.2 * max(extents.x, extents.z)
  }
}
