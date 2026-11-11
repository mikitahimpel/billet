import Pet

/// A shop piece the player can stand in the room: the model the scene draws and the room it takes.
/// Sizes are metres, as the shop's catalog fixes them.
public struct DecorItem: Equatable, Sendable, Identifiable {
  public enum Fit: Equatable, Sendable {
    case width
    case height
  }

  public enum Mount: Equatable, Sendable {
    case floor
    case wall
  }

  /// The id the shop sells it under, such as `armchair`.
  public let id: String
  /// The shop's model, which the shop draws; the room draws `assetName`.
  public let model: String

  /// The light copy the room draws: one mesh of at most `DecorItem.triangleBudget` triangles, from
  /// `tools/decor-lod`.
  public var assetName: String { "Decor_\(id)" }

  public static let triangleBudget = 5_000
  /// Most mesh parts (one per material) a model may have.
  public static let partBudget = 3

  public let fit: Fit
  /// The measure `fit` names, scaled to this many metres.
  public let size: Double
  public let mount: Mount
  /// Floor space it takes, across and into the room, with a quarter turn of zero. A wall piece
  /// has its width in `width` and no depth.
  public let width: Double
  public let depth: Double
  /// A rug lies on the floor: other pieces stand on it, so it never blocks one.
  public let isFlat: Bool

  public init(
    id: String, model: String, fit: Fit, size: Double, mount: Mount, width: Double, depth: Double,
    isFlat: Bool = false
  ) {
    self.id = id
    self.model = model
    self.fit = fit
    self.size = size
    self.mount = mount
    self.width = width
    self.depth = depth
    self.isFlat = isFlat
  }

  /// The pieces the shop sells today. A treat, a style or a piece it does not list is nil.
  public static func item(shopID id: String) -> DecorItem? {
    table[id]
  }

  public static var all: [DecorItem] { order.compactMap { table[$0] } }

  /// What the player can place out of everything owned, in the shop's order.
  public static func placeable(among owned: Set<String>) -> [DecorItem] {
    all.filter { owned.contains($0.id) }
  }

  /// The pieces the pair starts with. The room is built with a lamp and a rug of its own, so these
  /// wait in the closet rather than standing a second one beside it.
  public static let starters: Set<String> = ["lamp", "rug"]

  private static let order = [
    "armchair", "bookcase", "donutbed", "lamp", "lantern", "monstera", "print", "rug", "teatable",
    "tower", "yarn", "mouse",
  ]

  private static let footprints: [String: (width: Double, depth: Double)] = [
    "armchair": (0.36, 0.3), "bookcase": (0.3, 0.12), "donutbed": (0.34, 0.34),
    "lamp": (0.14, 0.14), "lantern": (0.1, 0.1), "monstera": (0.22, 0.22),
    "print": (0.2, 0), "rug": (0.6, 0.6), "teatable": (0.26, 0.26), "tower": (0.2, 0.2),
    "yarn": (0.12, 0.12), "mouse": (0.08, 0.05),
  ]

  private static let table: [String: DecorItem] = {
    var items: [String: DecorItem] = [:]
    for id in order {
      guard let piece = ShopCatalog.standard.item("furniture-\(id)"),
        case .furniture(let model, let fit, let size, let mount) = piece.look,
        let space = footprints[id]
      else { continue }
      items[id] = DecorItem(
        id: id, model: model, fit: fit == .width ? .width : .height, size: size,
        mount: mount == .wall ? .wall : .floor, width: space.width, depth: space.depth,
        isFlat: id == "rug")
    }
    return items
  }()
}
