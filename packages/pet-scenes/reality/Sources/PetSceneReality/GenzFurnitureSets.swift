import Foundation
import Pet

/// The furnished sets of the styled rooms. Each set is the same kinds of piece in its own
/// colours, placed to suit each room, with a few props of its own.
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
    switch style {
    case .windowSeat:
      layout.pieces = Self.windowSeatPieces(palette, furniture: furniture)
      layout.lamp = (GenzRoomPoint(2.15, 3.27, 1.74), GenzRoomPoint(2.15, 3.27, 0))
    case .sunsetLamp:
      layout.pieces = Self.sunsetPieces(palette, furniture: furniture)
      layout.lamp = (GenzRoomPoint(0.68, 0.62, 1.5), lamp.aim)
    case .nooki: break
    }
    return layout
  }

  private static func windowSeatPieces(
    _ palette: GenzFurniturePalette, furniture: RoomFurniture
  ) -> [Placement] {
    var pieces = [
      Placement(piece: palette.piece(.patternRug), centre: GenzRoomPoint(4.9, 4.3, 0)),
      Placement(piece: palette.piece(.quiltedDaybed), centre: GenzRoomPoint(3.8, 1.22, 0)),
      Placement(piece: palette.piece(.bookCrate), centre: GenzRoomPoint(2.15, 3.35, 0)),
      Placement(piece: palette.piece(.bookStack), centre: GenzRoomPoint(2.15, 3.28, 0.9)),
      Placement(piece: palette.piece(.pleatedLamp), centre: GenzRoomPoint(2.15, 3.27, 1.12)),
      Placement(piece: palette.piece(.snakePlant), centre: GenzRoomPoint(1.2, 0.28, 1.3)),
      Placement(
        piece: palette.piece(.phoneOnCharger), centre: GenzRoomPoint(5.2, 0.27, 1.3), yaw: 0.1),
      Placement(piece: palette.piece(.mugs), centre: GenzRoomPoint(2.5, 0.3, 1.3), yaw: 0.2),
      // Taped to the inside of the glass, beside the note.
      Placement(piece: palette.piece(.polaroids), centre: GenzRoomPoint(5.55, -0.11, 2.3)),
    ]
    switch furniture {
    case .original, .cosyNook:
      pieces += [
        Placement(piece: palette.piece(.leafyPlant), centre: GenzRoomPoint(1.3, 4.9, 0)),
        Placement(
          piece: palette.piece(.chairWithClothes), centre: GenzRoomPoint(6.7, 4.5, 0), yaw: -0.9),
      ]
    case .retroDen:
      pieces += [
        Placement(piece: palette.piece(.leafyPlant), centre: GenzRoomPoint(2.85, 5.2, 0)),
        Placement(piece: palette.piece(.bookCrate), centre: GenzRoomPoint(1.3, 4.9, 0)),
        Placement(
          piece: palette.piece(.recordPlayer), centre: GenzRoomPoint(1.3, 4.9, 0.9), yaw: 0.3),
        Placement(
          piece: palette.piece(.speaker), centre: GenzRoomPoint(6.9, 4.6, 0), yaw: -1.1),
      ]
    }
    return pieces
  }

  private static func sunsetPieces(
    _ palette: GenzFurniturePalette, furniture: RoomFurniture
  ) -> [Placement] {
    let lampCentre = GenzRoomPoint(0.68, 0.5, 0.9)
    let disc = GenzRoomPoint(3.1, 0, 3.05)
    var pieces = [
      Placement(piece: palette.piece(.patternRug), centre: GenzRoomPoint(3.9, 5.7, 0)),
      Placement(piece: palette.piece(.bookCrate), centre: GenzRoomPoint(0.58, 0.58, 0)),
      Placement(
        piece: palette.piece(.phoneOnCharger), centre: GenzRoomPoint(0.37, 0.75, 0.9), yaw: 0.3),
      Placement(
        piece: GenzPiece(.sunsetLamp), centre: lampCentre,
        yaw: atan2(lampCentre.x - disc.x, lampCentre.y - disc.y)),
      Placement(piece: palette.piece(.quiltedBed), centre: GenzRoomPoint(3.6, 1.7, 0)),
      Placement(
        piece: palette.piece(.sneakers), centre: GenzRoomPoint(2.95, 5.4, 0.03), yaw: -0.25),
      Placement(
        piece: palette.piece(.chairWithClothes), centre: GenzRoomPoint(1.2, 4.6, 0), yaw: 0.9),
      Placement(piece: palette.piece(.monstera), centre: GenzRoomPoint(1.1, 6.8, 0)),
      Placement(
        piece: palette.piece(.polaroids), centre: GenzRoomPoint(0.04, 5.6, 2.3), yaw: .pi / 2),
      Placement(piece: palette.piece(.mugs), centre: GenzRoomPoint(6.4, 2.9, 0), yaw: -0.4),
    ]
    switch furniture {
    case .original, .cosyNook:
      pieces.append(
        Placement(piece: palette.piece(.leafyPlant), centre: GenzRoomPoint(7.2, 6.8, 0)))
    case .retroDen:
      pieces += [
        Placement(piece: palette.piece(.bookCrate), centre: GenzRoomPoint(7.4, 6.6, 0)),
        Placement(
          piece: palette.piece(.recordPlayer), centre: GenzRoomPoint(7.4, 6.6, 0.9),
          yaw: -.pi / 2),
        Placement(
          piece: palette.piece(.speaker), centre: GenzRoomPoint(7.4, 5.2, 0), yaw: -.pi / 2),
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
    .quiltedBed: [GenzColour(0x5C3B28), GenzColour(0xD39B3A), GenzColour(0x2F7F7A)],
    .bookCrate: [GenzColour(0x6B4430), GenzColour(0xC2492F), GenzColour(0x2F6E6A)],
    .pleatedLamp: [GenzColour(0xB89A5A), GenzColour(0xE8B04B)],
    .leafyPlant: [GenzColour(0x2F2A28), GenzColour(0x4F7F45), GenzColour(0x2F5A35)],
    .patternRug: [GenzColour(0x7A2E22), GenzColour(0xD39B3A), GenzColour(0x2F5E5A)],
    .chairWithClothes: [GenzColour(0x3E2A1E), GenzColour(0x2F7F7A), GenzColour(0xD39B3A)],
    .mugs: [GenzColour(0xD39B3A), GenzColour(0x2F7F7A)],
    .polaroids: [GenzColour(0xE24B2D), GenzColour(0xD39B3A), GenzColour(0x2F7F7A)],
    .snakePlant: [GenzColour(0x2F2A28), GenzColour(0x3F7558), GenzColour(0x2D5A45)],
  ])
}
