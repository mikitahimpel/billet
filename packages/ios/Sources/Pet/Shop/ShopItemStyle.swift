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
    case .style: "Style"
    }
  }

  public var subtitle: String {
    switch self {
    case .materials: "Paint for the walls and the floor"
    case .furniture: "Pieces for the room"
    case .treats: "A little something for the cat"
    case .style: "Colours and finishes for the room"
    }
  }
}

extension ShopItem.Shelf {
  public var title: String {
    switch self {
    case .furniture: "Furniture"
    case .decor: "Decor"
    case .views: "Window views"
    case .cat: "Cat items"
    }
  }

  public var subtitle: String {
    switch self {
    case .furniture: "Big pieces for the floor"
    case .decor: "For a shelf, the seat or the wall"
    case .views: "What the window looks out on"
    case .cat: "Treats, toys and beds"
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
    case .style(.curtains): "curtains.closed"
    case .style(.fairy): "sparkles"
    case .style(.view): "window.horizontal"
    case .style(.wall), .style(.floor): "paintbrush.fill"
    }
  }

  public var tint: Swatch {
    switch look {
    case .material(_, let tone): tone.swatch
    case .furniture: Palette.woodLit
    case .treat: Palette.gold
    case .style: Palette.lightWarm
    }
  }

  /// What the item is, in a few words, for a card.
  public var detail: String {
    switch look {
    case .furniture(_, _, _, let mount): mount == .wall ? "Hangs on the wall" : "Stands in the room"
    case .material(let surface, _): surface == .wall ? "Paints the walls" : "Covers the floor"
    case .treat: "Used up when given"
    case .style(.view): "A view through your window"
    case .style: "Chosen in the Style tab"
    }
  }
}

extension ShopItem {
  /// What the cat does with it, for the things made for the cat. `nil` for the rest.
  public var catReaction: String? {
    switch id {
    case "furniture-donutbed": "Curls up inside and won't come out"
    case "furniture-tower": "Climbs to the top and watches you both"
    case "furniture-yarn": "Bats it under the sofa, then waits"
    case "furniture-mouse": "Pounces, then pretends it didn't"
    case "furniture-idol-catbed": "Kneads it, then naps all afternoon"
    case "furniture-idol-cattree": "Naps on the highest shelf"
    case "furniture-idol-scratchpost": "Stretches up tall and scratches"
    case "treat-fish": "Purrs before it's even unwrapped"
    case "treat-cookie": "Crunches it, then asks for another"
    case "treat-milk": "Laps it up, whiskers all white"
    default: nil
    }
  }
}

extension ShopItem {
  /// The Style tab's choice it is, for a style.
  public var styleChoice: RoomStyleItem? {
    if case .style(let choice) = look { choice } else { nil }
  }
}
