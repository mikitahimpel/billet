import Foundation
import RealityKit

/// The furniture and props of the styled rooms. Each piece is one material per part, with two or
/// three colour slots, so a shop variant is the same piece with other colours.
///
/// A piece is built in its own room units with its near corner on the floor at the origin, `x`
/// along its length and `y` out towards the viewer, as in ``GenzRoomPoint``.
struct GenzPiece: Hashable, Sendable {
  enum Kind: String, CaseIterable, Sendable {
    case phoneOnCharger
    case daybed
    case milkCrate
    case bookStack
    case thriftLamp
    case roundRug
    case snakePlant
    case quiltedDaybed
    case bookCrate
    case pleatedLamp
    case leafyPlant
    case patternRug
    case mugs
    case polaroids
    case recordPlayer
    case speaker
    case windowBench
    case bookshelf
    case sideTable
    case knitPouf
    case catBed
    case wallShelves
    case stringLights
    case cardigan
    case candles
    case pillowLarge
    case pillowLinen
    case pillowSquare
    case pillowSmall
    case blanket
    // Generated (FLUX.2-klein → Idol), each one model with its colour baked on: see IdolProp.
    case idolBeanBag
    case idolFloorLamp
    case idolThrow
    case idolMonstera
    case idolCactus
    case idolBooks
    case idolRecordPlayer
    case idolMugs
    case idolStringLights
    case idolRug
    case idolCatBed
    case idolDesk
    case idolArmchair
    case idolFloorCushionTerracotta
    case idolFloorCushionSage
    case idolFrameLandscape
    case idolPosterMoon
    case idolClock
    case idolFishTank
    case idolCatTree
    case idolScratchPost
    case idolFiddleFig
    case idolPothos
    case idolSucculents
    case idolGuitar
    case idolTeaSet
    case idolRadio
    case idolGlobe
    case idolLavaLamp
    case idolNeonHeart
    case idolBeanBagSage
    case idolBeanBagTerracotta
    case idolYarnBasket
    // The Nooki cabin's furniture.
    case cabinRug
    case cabinBed
    case cabinCatTree
    case cabinNightstand
    case cabinPlant
    case cabinBasket
    case cabinStoolLamp
    case cabinBooks
  }

  var kind: Kind
  /// The colours of the piece's slots, in the order ``Kind/slotNames`` lists them.
  var slots: [GenzColour]

  init(_ kind: Kind, slots: [GenzColour]? = nil) {
    self.kind = kind
    self.slots = slots ?? kind.standardSlots
  }

  func slot(_ index: Int) -> GenzColour {
    slots.indices.contains(index) ? slots[index] : kind.standardSlots[index]
  }
}

extension GenzPiece.Kind {
  /// What each colour slot paints.
  var slotNames: [String] {
    switch self {
    case .phoneOnCharger: ["case", "screen", "cable"]
    case .daybed: ["frame", "linen", "throw"]
    case .milkCrate: ["crate", "inside"]
    case .bookStack: ["lower", "upper"]
    case .thriftLamp: ["brass", "shade"]
    case .roundRug: ["edge", "middle"]
    case .snakePlant: ["pot", "leaf", "stripe"]
    case .quiltedDaybed: ["frame", "quilt", "throw"]
    case .bookCrate: ["crate", "books", "more books"]
    case .pleatedLamp: ["brass", "shade"]
    case .leafyPlant: ["pot", "leaf", "dark leaf"]
    case .patternRug: ["edge", "ring", "pattern"]
    case .mugs: ["mug", "other mug"]
    case .polaroids: ["print", "print", "print"]
    case .recordPlayer: ["wood", "label", "metal"]
    case .speaker: ["wood", "grille", "cone"]
    case .windowBench: ["wood", "cushion", "throw"]
    case .bookshelf: ["wood", "books", "more books"]
    case .sideTable: ["wood", "magazine"]
    case .knitPouf: ["knit", "button"]
    case .catBed: ["fleece", "blanket"]
    case .wallShelves: ["wood", "pot", "vase"]
    case .stringLights: ["wire", "bulbs"]
    case .cardigan: ["knit", "buttons"]
    case .candles: ["wax", "dish"]
    case .idolBeanBag, .idolFloorLamp, .idolThrow, .idolMonstera, .idolCactus, .idolBooks,
      .idolRecordPlayer, .idolMugs, .idolStringLights, .idolRug, .idolCatBed, .idolDesk,
      .idolArmchair, .idolFloorCushionTerracotta, .idolFloorCushionSage, .idolFrameLandscape,
      .idolPosterMoon, .idolClock, .idolFishTank, .idolCatTree, .idolScratchPost, .idolFiddleFig,
      .idolPothos, .idolSucculents, .idolGuitar, .idolTeaSet, .idolRadio, .idolGlobe, .idolLavaLamp,
      .idolNeonHeart, .idolBeanBagSage, .idolBeanBagTerracotta, .idolYarnBasket:
      []
    case .pillowLarge, .pillowLinen, .pillowSquare, .pillowSmall: ["fabric"]
    case .blanket: ["knit"]
    case .cabinRug: ["edge", "middle"]
    case .cabinBed: ["plush", "shade"]
    case .cabinCatTree: ["rope", "carpet", "toy"]
    case .cabinNightstand: ["wood", "drawers", "plant"]
    case .cabinPlant: ["pot", "leaf", "dark leaf"]
    case .cabinBasket: ["wicker", "yarn", "more yarn"]
    case .cabinStoolLamp: ["wood", "shade"]
    case .cabinBooks: ["lower", "upper"]
    }
  }

  var standardSlots: [GenzColour] {
    switch self {
    case .phoneOnCharger: [GenzColour(0x0B0A0E), GenzColour(0x9FB7D9), GenzColour(0xEDE3D8)]
    case .daybed: [GenzColour(0x323848), GenzColour(0xAEB6C4), GenzColour(0xB4553F)]
    case .milkCrate: [GenzColour(0x7A3B30), GenzColour(0x5C2B23)]
    case .bookStack: [GenzColour(0xD8C7A6), GenzColour(0x4F6B8A)]
    case .thriftLamp: [GenzColour(0xC9A86A), GenzColour(0xF3E3C3)]
    case .roundRug: [GenzColour(0x3B4A63), GenzColour(0x4A5C7A)]
    case .snakePlant: [GenzColour(0xD9CBB3), GenzColour(0x3F7558), GenzColour(0x2D5A45)]
    case .quiltedDaybed: [GenzColour(0xB0825A), GenzColour(0xEFE2CC), GenzColour(0xD9A441)]
    case .bookCrate: [GenzColour(0xC4935F), GenzColour(0xC2603F), GenzColour(0x8FA67E)]
    case .pleatedLamp: [GenzColour(0xC9A86A), GenzColour(0xF6E6C8)]
    case .leafyPlant: [GenzColour(0xC46E4A), GenzColour(0x5E8F4E), GenzColour(0x3F6E3A)]
    case .patternRug: [GenzColour(0xD9C3A0), GenzColour(0xC27A55), GenzColour(0xEFE2CC)]
    case .mugs: [GenzColour(0xE9DCC6), GenzColour(0xC9694D)]
    case .polaroids: [GenzColour(0xE9A07A), GenzColour(0x8DB0C9), GenzColour(0xA9C48E)]
    case .recordPlayer: [GenzColour(0x6B4430), GenzColour(0xE24B2D), GenzColour(0xB8B2A8)]
    case .speaker: [GenzColour(0x5C3B28), GenzColour(0x2A2421), GenzColour(0x1B1817)]
    case .windowBench: [GenzColour(0xC79A6B), GenzColour(0xEADCC6), GenzColour(0xD9A441)]
    case .bookshelf: [GenzColour(0xB98A5E), GenzColour(0xC2603F), GenzColour(0x8FA67E)]
    case .sideTable: [GenzColour(0xA97850), GenzColour(0xC27A55)]
    case .knitPouf: [GenzColour(0xE8D5B5), GenzColour(0xB89A6A)]
    case .catBed: [GenzColour(0xF1E6D6), GenzColour(0xD99A8A)]
    case .wallShelves: [GenzColour(0xB98A5E), GenzColour(0xC46E4A), GenzColour(0xE9DCC6)]
    case .stringLights: [GenzColour(0x3A3028), GenzColour(0xFFD58A)]
    case .cardigan: [GenzColour(0xD49A86), GenzColour(0xF1E6D6)]
    case .candles: [GenzColour(0xF3E8D6), GenzColour(0xC46E4A)]
    case .idolBeanBag, .idolFloorLamp, .idolThrow, .idolMonstera, .idolCactus, .idolBooks,
      .idolRecordPlayer, .idolMugs, .idolStringLights, .idolRug, .idolCatBed, .idolDesk,
      .idolArmchair, .idolFloorCushionTerracotta, .idolFloorCushionSage, .idolFrameLandscape,
      .idolPosterMoon, .idolClock, .idolFishTank, .idolCatTree, .idolScratchPost, .idolFiddleFig,
      .idolPothos, .idolSucculents, .idolGuitar, .idolTeaSet, .idolRadio, .idolGlobe, .idolLavaLamp,
      .idolNeonHeart, .idolBeanBagSage, .idolBeanBagTerracotta, .idolYarnBasket:
      []
    case .pillowLarge: [GenzColour(0xEADCC6).shaded(0.35)]
    case .pillowLinen: [GenzColour(0xC2603F)]
    case .pillowSquare: [GenzColour(0x8FA67E)]
    case .pillowSmall: [GenzColour(0xD9A441)]
    case .blanket: [GenzColour(0xD9A441)]
    case .cabinRug: [GenzColour(NookiCabin.Tone.rugEdge), GenzColour(NookiCabin.Tone.rug)]
    case .cabinBed: [GenzColour(NookiCabin.Tone.plush), GenzColour(NookiCabin.Tone.plushShade)]
    case .cabinCatTree:
      [
        GenzColour(0xD9B98C), GenzColour(NookiCabin.Tone.plushShade),
        GenzColour(NookiCabin.Tone.blanket),
      ]
    case .cabinNightstand:
      [
        GenzColour(NookiCabin.Tone.wood), GenzColour(NookiCabin.Tone.woodLight),
        GenzColour(NookiCabin.Tone.leaf),
      ]
    case .cabinPlant:
      [
        GenzColour(NookiCabin.Tone.pot), GenzColour(NookiCabin.Tone.leaf),
        GenzColour(NookiCabin.Tone.leafDark),
      ]
    case .cabinBasket:
      [GenzColour(0xC9A06A), GenzColour(NookiCabin.Tone.blanket), GenzColour(0x9DB08A)]
    case .cabinStoolLamp: [GenzColour(NookiCabin.Tone.wood), GenzColour(0xFFE2AE)]
    case .cabinBooks: [GenzColour(0x7C9A7E), GenzColour(0xE3B45C)]
    }
  }

  /// A pillow's shape: its width and height standing up, whether it is knitted or linen, and how
  /// far it leans over to one side. Zero for anything that is not a pillow.
  var pillow: (width: Float, height: Float, knit: Bool, roll: Float) {
    switch self {
    case .pillowLarge: (1.2, 1.0, true, 0.07)
    case .pillowLinen: (1.05, 0.9, false, -0.05)
    case .pillowSquare: (0.95, 0.84, false, 0.09)
    case .pillowSmall: (0.74, 0.68, true, -0.12)
    default: (0, 0, false, 0)
    }
  }

  var isPillow: Bool { pillow.width > 0 }

  var title: String {
    switch self {
    case .phoneOnCharger: "Phone on charger"
    case .daybed: "Daybed"
    case .milkCrate: "Milk crate"
    case .bookStack: "Book stack"
    case .thriftLamp: "Pleated thrift lamp"
    case .roundRug: "Round rug"
    case .snakePlant: "Snake plant"
    case .quiltedDaybed: "Quilted daybed"
    case .bookCrate: "Crate of books"
    case .pleatedLamp: "Pleated lamp"
    case .leafyPlant: "Leafy plant"
    case .patternRug: "Patterned rug"
    case .mugs: "Mugs"
    case .polaroids: "Polaroids"
    case .recordPlayer: "Record player"
    case .speaker: "Speaker"
    case .windowBench: "Window seat"
    case .bookshelf: "Bookshelf"
    case .sideTable: "Side table"
    case .knitPouf: "Knitted pouf"
    case .catBed: "Cat bed"
    case .wallShelves: "Wall shelves"
    case .stringLights: "String lights"
    case .cardigan: "Cardigan"
    case .candles: "Candles"
    case .idolBeanBag, .idolFloorLamp, .idolThrow, .idolMonstera, .idolCactus, .idolBooks,
      .idolRecordPlayer, .idolMugs, .idolStringLights, .idolRug, .idolCatBed, .idolDesk,
      .idolArmchair, .idolFloorCushionTerracotta, .idolFloorCushionSage, .idolFrameLandscape,
      .idolPosterMoon, .idolClock, .idolFishTank, .idolCatTree, .idolScratchPost, .idolFiddleFig,
      .idolPothos, .idolSucculents, .idolGuitar, .idolTeaSet, .idolRadio, .idolGlobe, .idolLavaLamp,
      .idolNeonHeart, .idolBeanBagSage, .idolBeanBagTerracotta, .idolYarnBasket:
      idol?.title ?? ""
    case .pillowLarge: "Big knit pillow"
    case .pillowLinen: "Linen pillow"
    case .pillowSquare: "Square pillow"
    case .pillowSmall: "Small knit pillow"
    case .blanket: "Blanket"
    case .cabinRug: "Round rug"
    case .cabinBed: "Plush cat bed"
    case .cabinCatTree: "Cat tree"
    case .cabinNightstand: "Nightstand"
    case .cabinPlant: "Tall plant"
    case .cabinBasket: "Yarn basket"
    case .cabinStoolLamp: "Stool lamp"
    case .cabinBooks: "Books"
    }
  }

  /// Its footprint and height in room units, for fitting it into the shop's metres.
  var size: GenzRoomPoint {
    switch self {
    case .phoneOnCharger: GenzRoomPoint(0.34, 0.2, 0.03)
    case .daybed: GenzRoomPoint(6.6, 2.4, 1.34)
    case .milkCrate: GenzRoomPoint(0.9, 0.9, 0.75)
    case .bookStack: GenzRoomPoint(0.7, 0.55, 0.22)
    case .thriftLamp: GenzRoomPoint(1, 1, 1.0)
    case .roundRug: GenzRoomPoint(2.5, 2.5, 0.03)
    case .snakePlant: GenzRoomPoint(0.5, 0.5, 1.6)
    case .quiltedDaybed: GenzRoomPoint(6.6, 2.4, 1.34)
    case .bookCrate: GenzRoomPoint(0.9, 0.9, 0.9)
    case .pleatedLamp: GenzRoomPoint(1, 1, 1.1)
    case .leafyPlant: GenzRoomPoint(1.2, 1.2, 1.9)
    case .patternRug: GenzRoomPoint(2.8, 2.8, 0.03)
    case .mugs: GenzRoomPoint(0.6, 0.3, 0.2)
    case .polaroids: GenzRoomPoint(1.6, 0.04, 1.1)
    case .recordPlayer: GenzRoomPoint(1.1, 0.85, 0.3)
    case .speaker: GenzRoomPoint(0.6, 0.56, 1)
    case .windowBench: GenzRoomPoint(6.4, 1.6, 1.3)
    case .bookshelf: GenzRoomPoint(1.6, 0.6, 3.4)
    case .sideTable: GenzRoomPoint(1, 1, 0.92)
    case .knitPouf: GenzRoomPoint(0.9, 0.9, 0.5)
    case .catBed: GenzRoomPoint(1, 1, 0.36)
    case .wallShelves: GenzRoomPoint(1.4, 0.32, 1.2)
    case .stringLights: GenzRoomPoint(5.6, 0.08, 0.5)
    case .cardigan: GenzRoomPoint(1.4, 1.25, 0.2)
    case .candles: GenzRoomPoint(0.5, 0.4, 0.3)
    case .idolBeanBag, .idolFloorLamp, .idolThrow, .idolMonstera, .idolCactus, .idolBooks,
      .idolRecordPlayer, .idolMugs, .idolStringLights, .idolRug, .idolCatBed, .idolDesk,
      .idolArmchair, .idolFloorCushionTerracotta, .idolFloorCushionSage, .idolFrameLandscape,
      .idolPosterMoon, .idolClock, .idolFishTank, .idolCatTree, .idolScratchPost, .idolFiddleFig,
      .idolPothos, .idolSucculents, .idolGuitar, .idolTeaSet, .idolRadio, .idolGlobe, .idolLavaLamp,
      .idolNeonHeart, .idolBeanBagSage, .idolBeanBagTerracotta, .idolYarnBasket:
      idol.map { prop in
        let size = prop.metres * GenzRoomPoint.perMetre
        return GenzRoomPoint(size.x, size.y, size.z)
      } ?? GenzRoomPoint(1, 1, 1)
    case .pillowLarge, .pillowLinen, .pillowSquare, .pillowSmall:
      GenzRoomPoint(pillow.width + 0.12, 0.7, pillow.height + 0.07)
    case .blanket: GenzRoomPoint(1.3, 0.84, 0.3)
    case .cabinRug: GenzRoomPoint(3.96, 3.96, 0.02)
    case .cabinBed: GenzRoomPoint(2.15, 2.15, 0.45)
    case .cabinCatTree: GenzRoomPoint(1.24, 1.24, 2.3)
    case .cabinNightstand: GenzRoomPoint(1.32, 1.32, 2.0)
    case .cabinPlant: GenzRoomPoint(1.2, 1.2, 1.85)
    case .cabinBasket: GenzRoomPoint(1.0, 1.0, 0.71)
    case .cabinStoolLamp: GenzRoomPoint(0.7, 0.7, 1.66)
    case .cabinBooks: GenzRoomPoint(0.8, 0.7, 0.28)
    }
  }
}

extension GenzColour {
  /// The colour moved towards white by `amount`, from 0 to 1, or towards black for a negative one.
  func shaded(_ amount: Float) -> GenzColour {
    func channel(_ value: Float) -> UInt32 {
      let moved = amount > 0 ? value + (1 - value) * amount : value * (1 + amount)
      return UInt32((min(max(moved, 0), 1) * 255).rounded())
    }
    return GenzColour(channel(red) << 16 | channel(green) << 8 | channel(blue))
  }

  /// The colour `amount` of the way from `start` to `end`, each channel on its own.
  static func mix(_ start: GenzColour, _ end: GenzColour, by amount: Float) -> GenzColour {
    func channel(_ from: Float, _ to: Float) -> UInt32 {
      UInt32((min(max(from + (to - from) * amount, 0), 1) * 255).rounded())
    }
    return GenzColour(
      channel(start.red, end.red) << 16 | channel(start.green, end.green) << 8
        | channel(start.blue, end.blue))
  }
}

@MainActor
extension GenzKit {
  /// The piece as an entity, its near floor corner at the origin.
  func build(_ piece: GenzPiece) -> Entity {
    let root = Entity()
    root.name = "genz-\(piece.kind.rawValue)"
    let parts: [Entity]
    switch piece.kind {
    case .phoneOnCharger: parts = phone(piece)
    case .daybed: parts = daybed(piece)
    case .milkCrate: parts = milkCrate(piece)
    case .bookStack: parts = bookStack(piece)
    case .thriftLamp: parts = thriftLamp(piece)
    case .roundRug: parts = roundRug(piece)
    case .snakePlant: parts = snakePlant(piece)
    case .quiltedDaybed: parts = quiltedDaybed(piece)
    case .bookCrate: parts = bookCrate(piece)
    case .pleatedLamp: parts = pleatedLamp(piece)
    case .leafyPlant: parts = leafyPlant(piece)
    case .patternRug: parts = patternRug(piece)
    case .mugs: parts = mugs(piece)
    case .polaroids: parts = polaroids(piece)
    case .recordPlayer: parts = recordPlayer(piece)
    case .speaker: parts = speaker(piece)
    case .windowBench: parts = windowBench(piece)
    case .bookshelf: parts = bookshelf(piece)
    case .sideTable: parts = sideTable(piece)
    case .knitPouf: parts = knitPouf(piece)
    case .catBed: parts = catBed(piece)
    case .wallShelves: parts = wallShelves(piece)
    case .stringLights: parts = stringLights(piece)
    case .cardigan: parts = cardigan(piece)
    case .candles: parts = candles(piece)
    case .idolBeanBag, .idolFloorLamp, .idolThrow, .idolMonstera, .idolCactus, .idolBooks,
      .idolRecordPlayer, .idolMugs, .idolStringLights, .idolRug, .idolCatBed, .idolDesk,
      .idolArmchair, .idolFloorCushionTerracotta, .idolFloorCushionSage, .idolFrameLandscape,
      .idolPosterMoon, .idolClock, .idolFishTank, .idolCatTree, .idolScratchPost, .idolFiddleFig,
      .idolPothos, .idolSucculents, .idolGuitar, .idolTeaSet, .idolRadio, .idolGlobe, .idolLavaLamp,
      .idolNeonHeart, .idolBeanBagSage, .idolBeanBagTerracotta, .idolYarnBasket:
      parts = piece.kind.idol.map(idolParts) ?? []
    case .pillowLarge, .pillowLinen, .pillowSquare, .pillowSmall: parts = pillow(piece)
    case .blanket: parts = blanket(piece)
    case .cabinRug: parts = cabinRug(piece)
    case .cabinBed: parts = cabinBed(piece)
    case .cabinCatTree: parts = cabinCatTree(piece)
    case .cabinNightstand: parts = cabinNightstand(piece)
    case .cabinPlant: parts = cabinPlant(piece)
    case .cabinBasket: parts = cabinBasket(piece)
    case .cabinStoolLamp: parts = cabinStoolLamp(piece)
    case .cabinBooks: parts = cabinBooks(piece)
    }
    for part in parts { root.addChild(part) }
    return root
  }

  private func phone(_ piece: GenzPiece) -> [Entity] {
    [
      block(0, 0, 0, 0.34, 0.2, 0.025, matte(piece.slot(0))),
      block(0.02, 0.02, 0.025, 0.3, 0.16, 0.006, glow(piece.slot(1))),
      block(0.15, 0.2, 0.004, 0.03, 0.5, 0.02, matte(piece.slot(2))),
    ]
  }

  private func daybed(_ piece: GenzPiece) -> [Entity] {
    let frame = matte(piece.slot(0))
    let throwColour = matte(piece.slot(2))
    return [
      block(0, 0, 0, 6.6, 2.4, 0.45, frame),
      block(0.06, 0.04, 0.45, 6.48, 2.3, 0.34, matte(piece.slot(1))),
      // The pillows stand in front of the window sill, which reaches 0.57 into the room.
      block(0.3, 0.6, 0.79, 1.3, 0.45, 0.55, matte(piece.slot(1).shaded(0.45))),
      block(1.8, 0.6, 0.79, 1.3, 0.45, 0.5, matte(piece.slot(0).shaded(0.4))),
      block(3.4, 0.28, 0.79, 3.1, 2.08, 0.08, throwColour),
      block(3.4, 2.36, 0.25, 3.1, 0.06, 0.62, matte(piece.slot(2).shaded(-0.14))),
    ]
  }

  /// Slats on four sides, open at the top, with a darker floor.
  private func milkCrate(_ piece: GenzPiece) -> [Entity] {
    let crate = matte(piece.slot(0))
    var parts: [Entity] = [block(0.04, 0.04, 0, 0.82, 0.82, 0.05, matte(piece.slot(1)))]
    for z in [Float(0), 0.3, 0.62] {
      parts.append(block(0, 0, z, 0.9, 0.06, 0.13, crate))
      parts.append(block(0, 0.84, z, 0.9, 0.06, 0.13, crate))
      parts.append(block(0, 0.06, z, 0.06, 0.78, 0.13, crate))
      parts.append(block(0.84, 0.06, z, 0.06, 0.78, 0.13, crate))
    }
    for x in [Float(0), 0.84] {
      for y in [Float(0), 0.84] { parts.append(block(x, y, 0, 0.06, 0.06, 0.75, crate)) }
    }
    return parts
  }

  private func bookStack(_ piece: GenzPiece) -> [Entity] {
    [
      block(0, 0, 0, 0.7, 0.55, 0.12, matte(piece.slot(0))),
      block(0.05, 0.04, 0.12, 0.6, 0.48, 0.1, matte(piece.slot(1))),
    ]
  }

  /// A pleated shade: a cone of twelve faces. The bulb inside is named for the lamp light.
  private func thriftLamp(_ piece: GenzPiece) -> [Entity] {
    let brass = matte(piece.slot(0))
    let centre = GenzRoomPoint(0.5, 0.5, 0)
    let bulb = Entity()
    bulb.name = GenzRoom.bulbName
    bulb.position = centre.scene + [0, 0.62, 0]
    return [
      part(prism(sides: 6, radius: 0.12, top: 0.12, height: 0.05), brass, at: centre.scene),
      part(
        prism(sides: 6, radius: 0.04, top: 0.04, height: 0.5), brass,
        at: centre.scene + [0, 0.05, 0]),
      part(
        prism(sides: 12, radius: 0.5, top: 0.3, height: 0.5, turn: 0), glow(piece.slot(1)),
        at: centre.scene + [0, 0.48, 0]),
      bulb,
    ]
  }

  private func roundRug(_ piece: GenzPiece) -> [Entity] {
    let centre = GenzRoomPoint(1.25, 1.25, 0)
    return [
      part(
        prism(sides: 8, radius: 1.25, top: 1.25, height: 0.02, turn: 0.39),
        matte(piece.slot(0)), at: centre.scene),
      part(
        prism(sides: 8, radius: 0.8, top: 0.8, height: 0.03, turn: 0.39), matte(piece.slot(1)),
        at: centre.scene),
    ]
  }

  private func snakePlant(_ piece: GenzPiece) -> [Entity] {
    let centre = GenzRoomPoint(0.25, 0.25, 0)
    let basket: [SIMD2<Float>] = [
      [0, 0], [0.19, 0], [0.21, 0.02], [0.24, 0.3], [0.255, 0.32], [0.25, 0.34], [0.23, 0.33],
      [0, 0.32],
    ]
    var parts: [Entity] = [
      part(
        lathe("snake basket", basket, sides: 20, repeats: 6),
        matte(piece.slot(0), .linen, repeats: [6, 2]), at: centre.scene)
    ]
    let blade = slab("snake blade", outline: [[-0.06, 0], [0.06, 0], [0, 1.2]], depth: 0.02)
    let blades: [(turn: Float, lean: Float, length: Float)] = [
      (0, 0.2, 0.85), (1.3, 0.12, 1.1), (2.4, 0.18, 0.95), (3.6, 0.1, 0.75), (4.9, 0.25, 0.65),
    ]
    for (index, spec) in blades.enumerated() {
      let model = part(
        blade, matte(piece.slot(index.isMultiple(of: 2) ? 1 : 2)),
        at: centre.scene + [0, 0.3, 0],
        turn: simd_quatf(angle: spec.turn, axis: [0, 1, 0])
          * simd_quatf(angle: spec.lean, axis: [1, 0, 0]))
      model.scale = [1, spec.length, 1]
      parts.append(model)
    }
    return parts
  }
}
