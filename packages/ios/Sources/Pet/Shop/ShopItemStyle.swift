import DesignSystem

extension ShopItem.Tone {
  /// The palette swatch this tone is named after.
  public var swatch: Swatch {
    switch self {
    case .clayLit: Palette.clayLit
    case .clay: Palette.clay
    case .greenLit: Palette.greenLit
    case .green: Palette.green
    case .paperTurned: Palette.paperTurned
    case .woodLit: Palette.woodLit
    case .wood: Palette.wood
    case .woodShade: Palette.woodShade
    case .skyLit: Palette.skyLit
    case .lightWarm: Palette.lightWarm
    }
  }
}

extension ShopItem.Category {
  public var title: String {
    switch self {
    case .materials: "Materials"
    case .furniture: "Furniture"
    case .treats: "Treats"
    }
  }

  public var subtitle: String {
    switch self {
    case .materials: "Paint for the walls and the floor"
    case .furniture: "Pieces for the room"
    case .treats: "A little something for the cat"
    }
  }
}

extension ShopItem {
  /// A flat stand-in for the item where no 3D preview is shown.
  public var symbol: String {
    switch look {
    case .furniture:
      switch id {
      case "furniture-armchair": "chair.lounge.fill"
      case "furniture-bookcase": "books.vertical.fill"
      case "furniture-donutbed": "bed.double.fill"
      case "furniture-lamp": "lamp.floor.fill"
      case "furniture-lantern": "lightbulb.fill"
      case "furniture-monstera": "leaf.fill"
      case "furniture-print": "photo.artframe"
      case "furniture-rug": "oval.fill"
      case "furniture-teatable": "table.furniture.fill"
      case "furniture-tower": "cat.fill"
      case "furniture-yarn": "scribble.variable"
      default: "pawprint.fill"
      }
    case .material(let surface, _):
      surface == .wall ? "square.fill" : "rectangle.fill"
    case .treat(let shape):
      switch shape {
      case .fish: "fish.fill"
      case .cookie: "circle.hexagongrid.fill"
      case .milk: "cup.and.saucer.fill"
      }
    }
  }

  public var tint: Swatch {
    switch look {
    case .material(_, let tone): tone.swatch
    case .furniture: Palette.woodLit
    case .treat: Palette.gold
    }
  }

  /// What the item is, in a few words, for a card.
  public var detail: String {
    switch look {
    case .furniture(_, _, _, let mount): mount == .wall ? "Hangs on the wall" : "Stands in the room"
    case .material(let surface, _): surface == .wall ? "Paints the walls" : "Covers the floor"
    case .treat: "Used up when given"
    }
  }
}
