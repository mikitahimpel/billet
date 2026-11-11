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

  /// The model the room draws: a light copy of at most `DecorItem.triangleBudget` triangles
  /// (`tools/decor-lod`), or the prop's own model when it is that light already.
  public let assetName: String

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
    id: String, model: String, assetName: String, fit: Fit, size: Double, mount: Mount,
    width: Double, depth: Double, isFlat: Bool = false
  ) {
    self.id = id
    self.model = model
    self.assetName = assetName
    self.fit = fit
    self.size = size
    self.mount = mount
    self.width = width
    self.depth = depth
    self.isFlat = isFlat
  }

  /// The pieces the player can place, from `DecorCatalog.generated.swift`. A treat, a style or a piece
  /// it does not list is nil.
  public static func item(shopID id: String) -> DecorItem? {
    table[id]
  }

  public static var all: [DecorItem] { catalog }

  /// What the player can place out of everything owned, in the shop's order.
  public static func placeable(among owned: Set<String>) -> [DecorItem] {
    all.filter { owned.contains($0.id) }
  }

  /// The pieces the pair starts with. The room is built with a lamp and a rug of its own, so these
  /// wait in the closet rather than standing a second one beside it.
  public static let starters: Set<String> = ["lamp", "rug"]

  private static let table: [String: DecorItem] = Dictionary(
    uniqueKeysWithValues: catalog.map { ($0.id, $0) })
}
