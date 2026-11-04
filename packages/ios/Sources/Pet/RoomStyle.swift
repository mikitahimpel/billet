import Foundation

/// How the pair has done up the Window Seat: what covers the walls and the floor, the curtains
/// and how far they are drawn, the view through the window, and the colour of the fairy lights.
/// Both partners see the same room; the last change from either of them wins.
///
/// Each part decodes on its own, so a choice from a later release reads as that part's standard
/// look and leaves the others as they were.
public struct RoomStyle: Codable, Hashable, Sendable {
  public var wall: RoomWall
  public var floor: RoomFloor
  public var curtains: CurtainFabric
  public var drape: CurtainDrape
  /// The view through the window, or `nil` to show the one chosen in Settings.
  public var view: WindowView?
  public var fairy: FairyColour

  /// The room as it comes: night-blue walls, a plain floor, bare window, warm fairy lights.
  public static let standard = RoomStyle()

  public init(
    wall: RoomWall = .standard, floor: RoomFloor = .standard,
    curtains: CurtainFabric = .standard, drape: CurtainDrape = .standard,
    view: WindowView? = nil, fairy: FairyColour = .standard
  ) {
    self.wall = wall
    self.floor = floor
    self.curtains = curtains
    self.drape = drape
    self.view = view
    self.fairy = fairy
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func part<Part: RawRepresentable<String>>(_ key: CodingKeys) -> Part? {
      (try? container.decodeIfPresent(String.self, forKey: key)).flatMap { $0 }
        .flatMap(Part.init(rawValue:))
    }
    wall = part(.wall) ?? .standard
    floor = part(.floor) ?? .standard
    curtains = part(.curtains) ?? .standard
    drape = part(.drape) ?? .standard
    view = part(.view)
    fairy = part(.fairy) ?? .standard
  }

  /// The choice `item` makes, put into this style.
  public func with(_ item: RoomStyleItem) -> RoomStyle {
    var style = self
    switch item {
    case .wall(let wall): style.wall = wall
    case .floor(let floor): style.floor = floor
    case .curtains(let fabric): style.curtains = fabric
    case .view(let view): style.view = view
    case .fairy(let colour): style.fairy = colour
    }
    return style
  }

  /// Whether `item` is what this style shows now.
  public func shows(_ item: RoomStyleItem) -> Bool {
    switch item {
    case .wall(let wall): self.wall == wall
    case .floor(let floor): self.floor == floor
    case .curtains(let fabric): curtains == fabric
    case .view(let view): self.view == view
    case .fairy(let colour): fairy == colour
    }
  }
}

/// What covers the walls: a paint, or a wallpaper with a small repeating pattern.
public enum RoomWall: String, CaseIterable, Codable, Hashable, Sendable {
  case night, rose, peach, sage, oat, butter, terracotta, lavender, teal, cocoa
  case stripes, gingham, dots, trellis, sprigs

  public static let standard = RoomWall.night

  public var isWallpaper: Bool {
    switch self {
    case .night, .rose, .peach, .sage, .oat, .butter, .terracotta, .lavender, .teal, .cocoa: false
    case .stripes, .gingham, .dots, .trellis, .sprigs: true
    }
  }

  public var title: String {
    switch self {
    case .night: "Night blue"
    case .rose: "Dusty rose"
    case .peach: "Peach"
    case .sage: "Sage"
    case .oat: "Oat"
    case .butter: "Butter"
    case .terracotta: "Terracotta"
    case .lavender: "Lavender"
    case .teal: "Deep teal"
    case .cocoa: "Cocoa"
    case .stripes: "Candy stripe"
    case .gingham: "Sage gingham"
    case .dots: "Butter dots"
    case .trellis: "Teal trellis"
    case .sprigs: "Rose sprigs"
    }
  }

  /// The wall's colour, sRGB, and for a wallpaper the colour of its pattern.
  public var colours: (base: UInt32, pattern: UInt32?) {
    switch self {
    case .night: (0x1A2436, nil)
    case .rose: (0xC4908A, nil)
    case .peach: (0xE2A47F, nil)
    case .sage: (0x8EA488, nil)
    case .oat: (0xD8C6A5, nil)
    case .butter: (0xE5C878, nil)
    case .terracotta: (0xB56A4C, nil)
    case .lavender: (0xA497BE, nil)
    case .teal: (0x3E6C69, nil)
    case .cocoa: (0x6A4A3B, nil)
    case .stripes: (0xF1E4D2, 0xD9958E)
    case .gingham: (0xEDE8D8, 0x8EA488)
    case .dots: (0xE5C878, 0xF6EEDB)
    case .trellis: (0x3E6C69, 0xD8C6A5)
    case .sprigs: (0xF3EADB, 0xC4706E)
    }
  }
}

/// What covers the floor.
public enum RoomFloor: String, CaseIterable, Codable, Hashable, Sendable {
  /// The room's own dark floor.
  case plain
  case lightWood, darkWood, herringbone, tiles

  public static let standard = RoomFloor.plain

  public var title: String {
    switch self {
    case .plain: "Slate"
    case .lightWood: "Light oak"
    case .darkWood: "Dark walnut"
    case .herringbone: "Herringbone"
    case .tiles: "Terracotta tiles"
    }
  }

  /// The floor's main colour, sRGB, for its swatch.
  public var colour: UInt32 {
    switch self {
    case .plain: 0x2A2F3B
    case .lightWood: 0xC9A27A
    case .darkWood: 0x5E3F2C
    case .herringbone: 0xA97C55
    case .tiles: 0xB8674A
    }
  }
}

/// What hangs at the window, if anything.
public enum CurtainFabric: String, CaseIterable, Codable, Hashable, Sendable {
  case none, linen, sheer, rose, forest, gingham

  public static let standard = CurtainFabric.none

  public var title: String {
    switch self {
    case .none: "No curtains"
    case .linen: "Oat linen"
    case .sheer: "Sheer voile"
    case .rose: "Rose velvet"
    case .forest: "Forest velvet"
    case .gingham: "Red gingham"
    }
  }

  /// The fabric's colour, sRGB, and for a check the colour of its stripes.
  public var colours: (base: UInt32, pattern: UInt32?) {
    switch self {
    case .none: (0x000000, nil)
    case .linen: (0xE6DAC4, nil)
    case .sheer: (0xF4EFE6, nil)
    case .rose: (0x9C4C58, nil)
    case .forest: (0x2E5443, nil)
    case .gingham: (0xF4ECE0, 0xC2464A)
    }
  }
}

/// How far the curtains are drawn across the window.
public enum CurtainDrape: String, CaseIterable, Codable, Hashable, Sendable {
  case open, half, closed

  public static let standard = CurtainDrape.open

  public var title: String {
    switch self {
    case .open: "Open"
    case .half: "Half"
    case .closed: "Closed"
    }
  }

  /// How much of the window the curtains cover, from 0 to 1.
  public var cover: Double {
    switch self {
    case .open: 0.16
    case .half: 0.5
    case .closed: 1
    }
  }
}

/// The colour the fairy lights glow.
public enum FairyColour: String, CaseIterable, Codable, Hashable, Sendable {
  /// Whatever the lighting preset gives them, a warm white.
  case warm
  case candle, rose, lilac, ice, mint

  public static let standard = FairyColour.warm

  public var title: String {
    switch self {
    case .warm: "Warm white"
    case .candle: "Candle"
    case .rose: "Rose"
    case .lilac: "Lilac"
    case .ice: "Ice"
    case .mint: "Mint"
    }
  }

  /// The bulbs' colour as linear-ish RGB from 0 to 1, or `nil` to keep the preset's own.
  public var rgb: SIMD3<Float>? {
    switch self {
    case .warm: nil
    case .candle: [1, 0.62, 0.3]
    case .rose: [1, 0.55, 0.7]
    case .lilac: [0.8, 0.62, 1]
    case .ice: [0.64, 0.84, 1]
    case .mint: [0.56, 1, 0.76]
    }
  }

  /// The swatch's colour, sRGB.
  public var swatch: UInt32 {
    switch self {
    case .warm: 0xFFD99B
    case .candle: 0xFFA04D
    case .rose: 0xFF8DB3
    case .lilac: 0xCDA0FF
    case .ice: 0xA3D6FF
    case .mint: 0x8FFFC2
    }
  }
}

/// One choice in the Style tab, which may cost stamps to unlock.
public enum RoomStyleItem: Codable, Hashable, Sendable {
  case wall(RoomWall)
  case floor(RoomFloor)
  case curtains(CurtainFabric)
  /// A view through the window; `nil` follows the one chosen in Settings.
  case view(WindowView?)
  case fairy(FairyColour)

  /// The stamps it costs to unlock, or `nil` when it is free.
  public var price: Int? {
    switch self {
    case .wall(let wall):
      switch wall {
      case .night, .rose, .sage, .oat, .butter, .stripes: nil
      case .peach, .terracotta, .lavender: 6
      case .teal, .cocoa: 8
      case .gingham, .dots: 10
      case .trellis: 12
      case .sprigs: 14
      }
    case .floor(let floor):
      switch floor {
      case .plain, .lightWood: nil
      case .darkWood: 8
      case .tiles: 12
      case .herringbone: 14
      }
    case .curtains(let fabric):
      switch fabric {
      case .none, .linen: nil
      case .sheer: 8
      case .rose, .forest: 10
      case .gingham: 12
      }
    case .view(let view):
      switch view {
      case nil, .suburbNight, .rainySuburb, .snowyDecember, .summerCulDeSac: nil
      case .dormQuad, .fireEscape, .pinkDusk, .sunsetBeach, .forestCabin, .moonlitPeaks,
        .neonStreet, .rooftopsDusk, .autumnPark, .mistyLake, .desertStars:
        8
      }
    case .fairy(let colour):
      switch colour {
      case .warm, .rose: nil
      case .candle: 4
      case .lilac, .ice, .mint: 6
      }
    }
  }

  public var title: String {
    switch self {
    case .wall(let wall): wall.title
    case .floor(let floor): floor.title
    case .curtains(let fabric): fabric.title
    case .view(let view): view?.title ?? "As in Settings"
    case .fairy(let colour): colour.title
    }
  }

  /// The shop's id for it, stable across releases.
  public var shopID: ShopItem.ID {
    switch self {
    case .wall(let wall): "style-wall-\(wall.rawValue)"
    case .floor(let floor): "style-floor-\(floor.rawValue)"
    case .curtains(let fabric): "style-curtains-\(fabric.rawValue)"
    case .view(let view): "style-view-\(view?.rawValue ?? "settings")"
    case .fairy(let colour): "style-fairy-\(colour.rawValue)"
    }
  }

  /// Every choice, in the order the Style tab shows them.
  public static let all: [RoomStyleItem] =
    RoomWall.allCases.map(RoomStyleItem.wall) + RoomFloor.allCases.map(RoomStyleItem.floor)
    + CurtainFabric.allCases.map(RoomStyleItem.curtains)
    + ([nil] + WindowView.allCases).map(RoomStyleItem.view)
    + FairyColour.allCases.map(RoomStyleItem.fairy)

  /// The choice as the shop sells it, or `nil` when it is free.
  public var shopItem: ShopItem? {
    price.map { ShopItem(id: shopID, name: title, price: $0, look: .style(self)) }
  }
}
