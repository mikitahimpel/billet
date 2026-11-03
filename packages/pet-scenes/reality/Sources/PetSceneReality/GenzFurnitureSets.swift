import Foundation
import Pet

/// The room's furnished sets. Each set is the same kinds of piece in its own colours, with a few
/// props of its own.
extension GenzLayout {
  /// The room with `furniture` in place of its first pieces. The first set leaves it as it is.
  func furnished(_ furniture: RoomFurniture) -> GenzLayout {
    let palette: GenzFurniturePalette
    switch furniture {
    case .original: return self
    case .cosyNook: palette = .cosyNook
    case .retroDen: palette = .retroDen
    }
    var layout = self
    layout.furniture = furniture
    // The furnished sets put the cat on a piece of their own.
    layout.catTop = nil
    layout.pieces = Self.windowSeatPieces(palette, furniture: furniture)
    // Turned a little further round, so the bookshelf corner beside the seat is in view.
    layout.camera.yaw = 0.5
    layout.lamp = (
      GenzRoomPoint(Self.seatTableLamp.x, Self.seatTableLamp.y, Self.seatTableLamp.z + 0.62),
      GenzRoomPoint(Self.seatTableLamp.x, Self.seatTableLamp.y, 0)
    )
    return layout
  }

  /// Where the Window Seat's lamp stands: on the side table, by the seat's end.
  private static let seatTableLamp = GenzRoomPoint(1.08, 2.3, 0.92)

  /// A built-in seat under the window, the cat's place, with a bookshelf and wall shelves on the
  /// side wall under string lights, a side table with the lamp, and a pouf and a cat bed on the
  /// rug.
  private static func windowSeatPieces(
    _ palette: GenzFurniturePalette, furniture: RoomFurniture
  ) -> [Placement] {
    let wall = Float.pi / 2
    let lamp = seatTableLamp
    var pieces = [
      Placement(piece: palette.piece(.patternRug), centre: GenzRoomPoint(4.3, 3.75, 0)),
      Placement(piece: palette.piece(.windowBench), centre: GenzRoomPoint(3.8, 0.8, 0)),
      Placement(piece: palette.piece(.bookshelf), centre: GenzRoomPoint(0.3, 0.86, 0), yaw: wall),
      Placement(piece: palette.piece(.sideTable), centre: GenzRoomPoint(1.12, 2.4, 0)),
      Placement(piece: palette.piece(.pleatedLamp), centre: lamp),
      Placement(
        piece: palette.piece(.candles), centre: GenzRoomPoint(1.32, 2.68, 0.92), yaw: 0.4),
      Placement(
        piece: palette.piece(.wallShelves), centre: GenzRoomPoint(0.16, 4.4, 2.2), yaw: wall),
      Placement(
        piece: palette.piece(.stringLights), centre: GenzRoomPoint(0.04, 3.0, 4.35), yaw: wall),
      Placement(
        piece: palette.piece(.polaroids), centre: GenzRoomPoint(0.03, 2.75, 2.15), yaw: wall),
      Placement(
        piece: palette.piece(.cardigan), centre: GenzRoomPoint(3.75, 1.0, 1.3), yaw: 0.1),
      Placement(
        piece: palette.piece(.phoneOnCharger), centre: GenzRoomPoint(5.0, 0.95, 1.3), yaw: .pi + 0.2
      ),
      Placement(piece: palette.piece(.mugs), centre: GenzRoomPoint(2.55, 1.2, 1.3), yaw: 0.2),
      Placement(piece: palette.piece(.snakePlant), centre: GenzRoomPoint(0.42, 4.15, 0)),
      Placement(piece: palette.piece(.leafyPlant), centre: GenzRoomPoint(6.85, 2.35, 0)),
      Placement(piece: palette.piece(.catBed), centre: GenzRoomPoint(5.9, 4.35, 0), yaw: -0.3),
    ]
    switch furniture {
    case .original, .cosyNook:
      pieces.append(
        Placement(piece: palette.piece(.knitPouf), centre: GenzRoomPoint(3.0, 3.35, 0)))
    case .retroDen:
      pieces += [
        Placement(piece: palette.piece(.bookCrate), centre: GenzRoomPoint(2.75, 4.7, 0)),
        Placement(
          piece: palette.piece(.recordPlayer), centre: GenzRoomPoint(2.75, 4.7, 0.9), yaw: 0.3),
        Placement(
          piece: palette.piece(.speaker), centre: GenzRoomPoint(6.9, 4.4, 0), yaw: -1.1),
      ]
    }
    return pieces
  }
}

/// The colours of one furnished set, by kind of piece. A kind it leaves out keeps its own.
struct GenzFurniturePalette {
  var slots: [GenzPiece.Kind: [GenzColour]]

  func piece(_ kind: GenzPiece.Kind) -> GenzPiece { GenzPiece(kind, slots: slots[kind]) }

  /// Warm oak, cream and mustard, terracotta and sage.
  static let cosyNook = GenzFurniturePalette(slots: [:])

  /// Dark walnut, mustard and teal, with a red record label.
  static let retroDen = GenzFurniturePalette(slots: [
    .quiltedDaybed: [GenzColour(0x5C3B28), GenzColour(0xD39B3A), GenzColour(0x2F7F7A)],
    .bookCrate: [GenzColour(0x6B4430), GenzColour(0xC2492F), GenzColour(0x2F6E6A)],
    .pleatedLamp: [GenzColour(0xB89A5A), GenzColour(0xE8B04B)],
    .leafyPlant: [GenzColour(0x2F2A28), GenzColour(0x4F7F45), GenzColour(0x2F5A35)],
    .patternRug: [GenzColour(0x7A2E22), GenzColour(0xD39B3A), GenzColour(0x2F5E5A)],
    .mugs: [GenzColour(0xD39B3A), GenzColour(0x2F7F7A)],
    .polaroids: [GenzColour(0xE24B2D), GenzColour(0xD39B3A), GenzColour(0x2F7F7A)],
    .snakePlant: [GenzColour(0x2F2A28), GenzColour(0x3F7558), GenzColour(0x2D5A45)],
    .windowBench: [GenzColour(0x5C3B28), GenzColour(0xD39B3A), GenzColour(0x2F7F7A)],
    .bookshelf: [GenzColour(0x5C3B28), GenzColour(0xC2492F), GenzColour(0x2F6E6A)],
    .sideTable: [GenzColour(0x5C3B28), GenzColour(0xD39B3A)],
    .wallShelves: [GenzColour(0x5C3B28), GenzColour(0x2F7F7A), GenzColour(0xD39B3A)],
    .cardigan: [GenzColour(0x2F7F7A), GenzColour(0xD39B3A)],
    .catBed: [GenzColour(0xE8D9BE), GenzColour(0xC2492F)],
    .candles: [GenzColour(0xF3E8D6), GenzColour(0x2F7F7A)],
  ])
}
