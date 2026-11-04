import Foundation

/// A wall or the floor of the room.
public enum RoomSurface: String, Codable, Hashable, Sendable, CaseIterable {
  case wall
  case floor
}

/// One thing the shop sells.
public struct ShopItem: Codable, Hashable, Sendable, Identifiable {
  public typealias ID = String

  public enum Category: String, Codable, Hashable, Sendable, CaseIterable {
    case materials
    case furniture
    case treats
    /// Paints, floors, curtains, views and fairy lights for the Style tab. They are bought there,
    /// so the catalog's shelves hold none; ``RoomStyleItem/shopItem`` makes each one.
    case style

    /// The categories the shop and the closet show as shelves.
    public static let shelves: [Category] = [.materials, .furniture, .treats]
  }

  /// The groups the Shop tab shows its grid in, in order.
  public enum Shelf: String, Hashable, Sendable, CaseIterable {
    /// Big pieces that stand on the floor.
    case furniture
    /// Small things for a table top or the seat, and things hung on a wall.
    case decor
    /// Views through the window.
    case views
    /// Treats, toys, beds and climbing things for the cat.
    case cat
  }

  /// Where a piece of furniture stands.
  public enum Mount: String, Codable, Hashable, Sendable {
    case floor
    case wall
  }

  /// Which measure of a model its catalog size fixes.
  public enum Fit: String, Codable, Hashable, Sendable {
    case width
    case height
  }

  /// The colours a material can take, named after the palette swatch they come from.
  public enum Tone: String, Codable, Hashable, Sendable {
    case clayLit, clay, greenLit, green, paperTurned, woodLit, wood, woodShade, skyLit, lightWarm
  }

  public enum TreatShape: String, Codable, Hashable, Sendable {
    case fish
    case cookie
    case milk
  }

  /// What the item is, which also decides how it is used.
  public enum Look: Codable, Hashable, Sendable {
    /// A model from the Reality bundle, scaled so its `fit` measures `size` metres.
    case furniture(model: String, fit: Fit, size: Double, mount: Mount)
    case material(surface: RoomSurface, tone: Tone)
    case treat(shape: TreatShape)
    /// A choice in the Style tab, unlocked for good once bought.
    case style(RoomStyleItem)
  }

  public let id: ID
  public let name: String
  public let price: Int
  public let look: Look

  public init(id: ID, name: String, price: Int, look: Look) {
    self.id = id
    self.name = name
    self.price = price
    self.look = look
  }

  public var category: Category {
    switch look {
    case .furniture: .furniture
    case .material: .materials
    case .treat: .treats
    case .style: .style
    }
  }

  /// The Shop tab's group for it, or `nil` when the tab does not sell it: wall and floor paints and
  /// the room's other styles are chosen in the Style tab.
  public var shelf: Shelf? {
    switch look {
    case .furniture:
      if ShopCatalog.catPieces.contains(id) {
        .cat
      } else if ShopCatalog.decorPieces.contains(id) {
        .decor
      } else {
        .furniture
      }
    case .treat: .cat
    case .style(.view): .views
    case .material, .style: nil
    }
  }

  /// Whether buying it stands it in the room.
  public var isPlaceable: Bool {
    if case .furniture = look { true } else { false }
  }

  /// A treat is used up by use. Everything else stays.
  public var isConsumable: Bool { category == .treats }

  /// A material or a style is a permanent unlock, so one copy is all there is to own.
  public var ownsAtMostOne: Bool { category == .materials || category == .style }
}

/// Everything for sale. Static and local: it ships with the app.
public struct ShopCatalog: Codable, Hashable, Sendable {
  public let items: [ShopItem]

  public init(items: [ShopItem]) {
    self.items = items
  }

  public func item(_ id: ShopItem.ID) -> ShopItem? {
    items.first { $0.id == id }
  }

  public func items(in category: ShopItem.Category) -> [ShopItem] {
    items.filter { $0.category == category }
  }

  /// What the Shop tab shows on `shelf`. Window views are style choices, so they come from
  /// ``RoomStyleItem`` rather than this catalogue's items.
  public func items(on shelf: ShopItem.Shelf) -> [ShopItem] {
    switch shelf {
    case .views:
      RoomStyleItem.all.compactMap { style in
        if case .view = style { style.shopItem } else { nil }
      }
    case .furniture, .decor, .cat:
      items.filter { $0.shelf == shelf }
    }
  }

  /// Pieces for the cat rather than the room, by ID.
  static let catPieces: Set<ShopItem.ID> = [
    "furniture-donutbed", "furniture-tower", "furniture-yarn", "furniture-mouse",
    "furniture-idol-catbed", "furniture-idol-cattree", "furniture-idol-scratchpost",
  ]

  /// Small pieces for a top or the seat, and pieces hung on a wall, by ID. Everything else of the
  /// furniture stands on the floor.
  static let decorPieces: Set<ShopItem.ID> = [
    "furniture-lantern", "furniture-print",
    "furniture-idol-throwblanket", "furniture-idol-cactus", "furniture-idol-books",
    "furniture-idol-recordplayer", "furniture-idol-mugs", "furniture-idol-stringlights",
    "furniture-idol-pothos", "furniture-idol-succulents", "furniture-idol-teaset",
    "furniture-idol-radio", "furniture-idol-globe", "furniture-idol-lavalamp",
    "furniture-idol-yarnbasket", "furniture-idol-clock", "furniture-idol-frame_landscape",
    "furniture-idol-poster_moon", "furniture-idol-neonheart",
  ]

  public static let standard = ShopCatalog(items: materials + furniture + treats)

  /// This catalogue with the generated (Idol) pieces added beside its furniture, for the Labs
  /// pilot that compares them with the hand-made ones.
  public var withIdolProps: ShopCatalog {
    ShopCatalog(items: items + Self.idolProps.filter { item($0.id) == nil })
  }

  private static let materials: [ShopItem] = [
    material("wall-rose", "Rose wall", 10, .wall, .clayLit),
    material("wall-sage", "Sage wall", 10, .wall, .greenLit),
    material("wall-cream", "Cream wall", 12, .wall, .paperTurned),
    material("wall-dusk", "Dusk wall", 12, .wall, .skyLit),
    material("floor-oak", "Oak floor", 10, .floor, .woodLit),
    material("floor-walnut", "Walnut floor", 12, .floor, .woodShade),
    material("floor-moss", "Moss floor", 10, .floor, .green),
    material("floor-brick", "Brick floor", 12, .floor, .clay),
  ]

  private static let furniture: [ShopItem] = [
    piece("armchair", "Armchair", 30, "Item_armchair", .width, 0.4),
    piece("bookcase", "Bookcase", 34, "Item_bookcase", .height, 0.6),
    piece("donutbed", "Donut bed", 22, "Item_donutbed", .width, 0.4),
    piece("lamp", "Floor lamp", 24, "Item_lamp", .height, 0.46),
    piece("lantern", "Lantern", 14, "Item_lantern", .height, 0.15),
    piece("monstera", "Monstera", 18, "Item_monstera", .height, 0.55),
    piece("print", "Framed print", 16, "Item_print", .height, 0.26, mount: .wall),
    piece("rug", "Round rug", 20, "Item_rug", .width, 0.6),
    piece("teatable", "Tea table", 18, "Item_teatable", .height, 0.2),
    piece("tower", "Cat tower", 36, "Item_tower", .height, 0.6),
    piece("yarn", "Ball of yarn", 6, "Item_yarn", .width, 0.12),
    piece("mouse", "Toy mouse", 6, "Item_mouse", .height, 0.07),
  ]

  /// Made from a FLUX.2 picture by Idol, remeshed and baked onto one shared texture. Model names
  /// start with `Idol_`, and the models live in their own file beside the room's.
  static let idolProps: [ShopItem] = [
    idol("beanbag", "Bean bag", 26, .width, 0.4),
    idol("floorlamp", "Standing lamp", 24, .height, 0.75),
    idol("throwblanket", "Knitted throw", 14, .width, 0.25),
    idol("monstera", "Potted monstera", 18, .height, 0.55),
    idol("cactus", "Little cactus", 8, .height, 0.09),
    idol("books", "Pile of books", 10, .width, 0.14),
    idol("recordplayer", "Record player", 28, .width, 0.21),
    idol("mugs", "Two mugs", 8, .width, 0.11),
    idol("stringlights", "Coil of fairy lights", 12, .width, 0.18),
    idol("rug", "Woven rug", 20, .width, 0.6),
    idol("catbed", "Plush cat bed", 22, .width, 0.25),
    idol("desk", "Writing desk", 34, .width, 0.5),
    idol("armchair", "Round armchair", 32, .width, 0.4),
    idol("floorcushion_terracotta", "Terracotta floor cushion", 12, .width, 0.3),
    idol("floorcushion_sage", "Sage floor cushion", 12, .width, 0.3),
    idol("frame_landscape", "Sunset hills painting", 12, .width, 0.225, mount: .wall),
    idol("poster_moon", "Moon poster", 10, .height, 0.3, mount: .wall),
    idol("clock", "Wall clock", 14, .width, 0.16, mount: .wall),
    idol("fishtank", "Fishbowl on a stand", 36, .height, 0.35),
    idol("cattree", "Cat tree", 38, .height, 0.55),
    idol("scratchpost", "Scratching post", 16, .height, 0.3),
    idol("fiddlefig", "Fiddle leaf fig", 22, .height, 0.75),
    idol("pothos", "Trailing pothos", 12, .height, 0.175),
    idol("succulents", "Succulent trio", 10, .width, 0.15),
    idol("guitar", "Acoustic guitar", 30, .height, 0.5),
    idol("teaset", "Tea set", 14, .width, 0.18),
    idol("radio", "Wooden radio", 18, .width, 0.16),
    idol("globe", "Desk globe", 16, .height, 0.18),
    idol("lavalamp", "Lava lamp", 18, .height, 0.2),
    idol("neonheart", "Neon heart", 24, .width, 0.225, mount: .wall),
    idol("beanbag_sage", "Sage bean bag", 26, .width, 0.4),
    idol("beanbag_terracotta", "Terracotta bean bag", 26, .width, 0.4),
    idol("yarnbasket", "Basket of yarn", 12, .width, 0.2),
  ]

  private static let treats: [ShopItem] = [
    ShopItem(id: "treat-fish", name: "Dried fish", price: 3, look: .treat(shape: .fish)),
    ShopItem(id: "treat-cookie", name: "Cat cookie", price: 4, look: .treat(shape: .cookie)),
    ShopItem(id: "treat-milk", name: "Saucer of milk", price: 5, look: .treat(shape: .milk)),
  ]

  private static func material(
    _ id: String, _ name: String, _ price: Int, _ surface: RoomSurface, _ tone: ShopItem.Tone
  ) -> ShopItem {
    ShopItem(id: id, name: name, price: price, look: .material(surface: surface, tone: tone))
  }

  private static func idol(
    _ id: String, _ name: String, _ price: Int, _ fit: ShopItem.Fit, _ size: Double,
    mount: ShopItem.Mount = .floor
  ) -> ShopItem {
    ShopItem(
      id: "furniture-idol-\(id)", name: name, price: price,
      look: .furniture(model: "Idol_\(id)", fit: fit, size: size, mount: mount))
  }

  private static func piece(
    _ id: String, _ name: String, _ price: Int, _ model: String, _ fit: ShopItem.Fit,
    _ size: Double, mount: ShopItem.Mount = .floor
  ) -> ShopItem {
    ShopItem(
      id: "furniture-\(id)", name: name, price: price,
      look: .furniture(model: model, fit: fit, size: size, mount: mount))
  }
}
