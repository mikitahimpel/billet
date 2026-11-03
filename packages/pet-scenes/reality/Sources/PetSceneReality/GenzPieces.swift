import Foundation
import RealityKit

/// The furniture and props of the styled rooms. Each piece is one material per part, with two or
/// three colour slots, so a shop variant is the same piece with other colours.
///
/// A piece is built in its own room units with its near corner on the floor at the origin, `x`
/// along its length and `y` out towards the viewer, as in ``GenzRoomPoint``.
struct GenzPiece: Hashable, Sendable {
  enum Kind: String, CaseIterable, Sendable {
    case platformBed
    case cubeNightstand
    case sunsetLamp
    case checkeredRug
    case phoneOnCharger
    case sneakers
    case hoodiePile
    case monstera
    case posterFrame
    case daybed
    case milkCrate
    case bookStack
    case thriftLamp
    case roundRug
    case snakePlant
    case quiltedDaybed
    case quiltedBed
    case bookCrate
    case pleatedLamp
    case leafyPlant
    case patternRug
    case chairWithClothes
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
    case .platformBed: ["frame", "linen", "duvet"]
    case .cubeNightstand: ["body", "top"]
    case .sunsetLamp: ["body", "stem", "lens"]
    case .checkeredRug: ["light", "dark"]
    case .phoneOnCharger: ["case", "screen", "cable"]
    case .sneakers: ["upper", "sole"]
    case .hoodiePile: ["hoodie", "tee"]
    case .monstera: ["pot", "leaf", "vein"]
    case .posterFrame: ["frame", "print"]
    case .daybed: ["frame", "linen", "throw"]
    case .milkCrate: ["crate", "inside"]
    case .bookStack: ["lower", "upper"]
    case .thriftLamp: ["brass", "shade"]
    case .roundRug: ["edge", "middle"]
    case .snakePlant: ["pot", "leaf", "stripe"]
    case .quiltedDaybed: ["frame", "quilt", "throw"]
    case .quiltedBed: ["frame", "quilt", "throw"]
    case .bookCrate: ["crate", "books", "more books"]
    case .pleatedLamp: ["brass", "shade"]
    case .leafyPlant: ["pot", "leaf", "dark leaf"]
    case .patternRug: ["edge", "ring", "pattern"]
    case .chairWithClothes: ["wood", "jumper", "jeans"]
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
    }
  }

  var standardSlots: [GenzColour] {
    switch self {
    case .platformBed: [GenzColour(0x6B4C3B), GenzColour(0xDDD2C6), GenzColour(0x6F8C7A)]
    case .cubeNightstand: [GenzColour(0x5A4038), GenzColour(0x6A4C42)]
    case .sunsetLamp: [GenzColour(0x2A2530), GenzColour(0x3A3340), GenzColour(0xFFB066)]
    case .checkeredRug: [GenzColour(0xB9A893), GenzColour(0x5E7768)]
    case .phoneOnCharger: [GenzColour(0x0B0A0E), GenzColour(0x9FB7D9), GenzColour(0xEDE3D8)]
    case .sneakers: [GenzColour(0xF4F0EA), GenzColour(0xD9D0C4)]
    case .hoodiePile: [GenzColour(0x55405A), GenzColour(0x86A493)]
    case .monstera: [GenzColour(0xB97A55), GenzColour(0x3D7052), GenzColour(0x2F5A43)]
    case .posterFrame: [GenzColour(0x1C1622), GenzColour(0x2F4A42)]
    case .daybed: [GenzColour(0x323848), GenzColour(0xAEB6C4), GenzColour(0xB4553F)]
    case .milkCrate: [GenzColour(0x7A3B30), GenzColour(0x5C2B23)]
    case .bookStack: [GenzColour(0xD8C7A6), GenzColour(0x4F6B8A)]
    case .thriftLamp: [GenzColour(0xC9A86A), GenzColour(0xF3E3C3)]
    case .roundRug: [GenzColour(0x3B4A63), GenzColour(0x4A5C7A)]
    case .snakePlant: [GenzColour(0xD9CBB3), GenzColour(0x3F7558), GenzColour(0x2D5A45)]
    case .quiltedDaybed: [GenzColour(0xB0825A), GenzColour(0xEFE2CC), GenzColour(0xD9A441)]
    case .quiltedBed: [GenzColour(0xB0825A), GenzColour(0xEFE2CC), GenzColour(0xD9A441)]
    case .bookCrate: [GenzColour(0xC4935F), GenzColour(0xC2603F), GenzColour(0x8FA67E)]
    case .pleatedLamp: [GenzColour(0xC9A86A), GenzColour(0xF6E6C8)]
    case .leafyPlant: [GenzColour(0xC46E4A), GenzColour(0x5E8F4E), GenzColour(0x3F6E3A)]
    case .patternRug: [GenzColour(0xD9C3A0), GenzColour(0xC27A55), GenzColour(0xEFE2CC)]
    case .chairWithClothes: [GenzColour(0xA67B52), GenzColour(0xB75D4B), GenzColour(0x5B7290)]
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
    }
  }

  var title: String {
    switch self {
    case .platformBed: "Low platform bed"
    case .cubeNightstand: "Cube nightstand"
    case .sunsetLamp: "Sunset lamp"
    case .checkeredRug: "Checkered rug"
    case .phoneOnCharger: "Phone on charger"
    case .sneakers: "Sneakers"
    case .hoodiePile: "Hoodie pile"
    case .monstera: "Big monstera"
    case .posterFrame: "Poster frame"
    case .daybed: "Daybed"
    case .milkCrate: "Milk crate"
    case .bookStack: "Book stack"
    case .thriftLamp: "Pleated thrift lamp"
    case .roundRug: "Round rug"
    case .snakePlant: "Snake plant"
    case .quiltedDaybed: "Quilted daybed"
    case .quiltedBed: "Quilted bed"
    case .bookCrate: "Crate of books"
    case .pleatedLamp: "Pleated lamp"
    case .leafyPlant: "Leafy plant"
    case .patternRug: "Patterned rug"
    case .chairWithClothes: "Chair with clothes"
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
    }
  }

  /// Its footprint and height in room units, for fitting it into the shop's metres.
  var size: GenzRoomPoint {
    switch self {
    case .platformBed: GenzRoomPoint(4.8, 3.4, 1.18)
    case .cubeNightstand: GenzRoomPoint(1, 1, 1.02)
    case .sunsetLamp: GenzRoomPoint(0.52, 0.52, 0.76)
    case .checkeredRug: GenzRoomPoint(4, 3.5, 0.03)
    case .phoneOnCharger: GenzRoomPoint(0.34, 0.2, 0.03)
    case .sneakers: GenzRoomPoint(0.85, 0.8, 0.26)
    case .hoodiePile: GenzRoomPoint(1.4, 1.4, 0.35)
    case .monstera: GenzRoomPoint(2.4, 2.4, 3.4)
    case .posterFrame: GenzRoomPoint(1.05, 0.04, 1.9)
    case .daybed: GenzRoomPoint(6.6, 2.4, 1.34)
    case .milkCrate: GenzRoomPoint(0.9, 0.9, 0.75)
    case .bookStack: GenzRoomPoint(0.7, 0.55, 0.22)
    case .thriftLamp: GenzRoomPoint(1, 1, 1.0)
    case .roundRug: GenzRoomPoint(2.5, 2.5, 0.03)
    case .snakePlant: GenzRoomPoint(0.5, 0.5, 1.6)
    case .quiltedDaybed: GenzRoomPoint(6.6, 2.4, 1.34)
    case .quiltedBed: GenzRoomPoint(4.8, 3.4, 1.18)
    case .bookCrate: GenzRoomPoint(0.9, 0.9, 0.9)
    case .pleatedLamp: GenzRoomPoint(1, 1, 1.1)
    case .leafyPlant: GenzRoomPoint(1.2, 1.2, 1.9)
    case .patternRug: GenzRoomPoint(2.8, 2.8, 0.03)
    case .chairWithClothes: GenzRoomPoint(1.06, 1, 1.9)
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
    case .platformBed: parts = platformBed(piece)
    case .cubeNightstand: parts = cubeNightstand(piece)
    case .sunsetLamp: parts = sunsetLamp(piece)
    case .checkeredRug: parts = checkeredRug(piece)
    case .phoneOnCharger: parts = phone(piece)
    case .sneakers: parts = sneakers(piece)
    case .hoodiePile: parts = hoodiePile(piece)
    case .monstera: parts = monstera(piece)
    case .posterFrame: parts = posterFrame(piece)
    case .daybed: parts = daybed(piece)
    case .milkCrate: parts = milkCrate(piece)
    case .bookStack: parts = bookStack(piece)
    case .thriftLamp: parts = thriftLamp(piece)
    case .roundRug: parts = roundRug(piece)
    case .snakePlant: parts = snakePlant(piece)
    case .quiltedDaybed: parts = quiltedDaybed(piece)
    case .quiltedBed: parts = quiltedBed(piece)
    case .bookCrate: parts = bookCrate(piece)
    case .pleatedLamp: parts = pleatedLamp(piece)
    case .leafyPlant: parts = leafyPlant(piece)
    case .patternRug: parts = patternRug(piece)
    case .chairWithClothes: parts = chairWithClothes(piece)
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
    }
    for part in parts { root.addChild(part) }
    return root
  }

  private func platformBed(_ piece: GenzPiece) -> [Entity] {
    let frame = matte(piece.slot(0))
    let linen = matte(piece.slot(1))
    let duvet = matte(piece.slot(2))
    return [
      block(0, 0, 0, 4.8, 3.4, 0.5, frame),
      block(0.1, 0.08, 0.5, 4.6, 3.24, 0.38, linen),
      block(0.3, 0.2, 0.88, 1.6, 0.85, 0.3, matte(piece.slot(1).shaded(0.3))),
      block(2.1, 0.2, 0.88, 1.6, 0.85, 0.3, linen),
      block(0.05, 1.25, 0.55, 4.7, 0.4, 0.55, matte(piece.slot(2).shaded(0.18))),
      block(0.05, 1.65, 0.55, 4.7, 1.85, 0.47, duvet),
      block(0.05, 3.48, 0.2, 4.7, 0.05, 0.75, duvet),
    ]
  }

  private func cubeNightstand(_ piece: GenzPiece) -> [Entity] {
    [
      block(0, 0, 0, 1, 1, 0.96, matte(piece.slot(0))),
      block(0, 0, 0.96, 1, 1, 0.06, matte(piece.slot(1))),
      block(0.12, 0.98, 0.2, 0.76, 0.03, 0.04, matte(piece.slot(1))),
    ]
  }

  /// The lens sits on top and faces the wall behind, along -y.
  private func sunsetLamp(_ piece: GenzPiece) -> [Entity] {
    let body = matte(piece.slot(0))
    let towardsWall = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
    let head = part(
      prism(sides: 8, radius: 0.22, top: 0.24, height: 0.34), body, at: [0.26, 0.6, 0.43],
      turn: towardsWall)
    let lens = part(
      prism(sides: 8, radius: 0.17, top: 0.17, height: 0.02), glow(piece.slot(2)),
      at: [0.26, 0.6, 0.09], turn: towardsWall)
    lens.name = GenzRoom.lensName
    return [
      part(prism(sides: 8, radius: 0.22, top: 0.2, height: 0.1), body, at: [0.26, 0, 0.26]),
      part(
        prism(sides: 6, radius: 0.06, top: 0.06, height: 0.3), matte(piece.slot(1)),
        at: [0.26, 0.1, 0.26]),
      part(box([0.16, 0.12, 0.16]), matte(piece.slot(1)), at: [0.26, 0.44, 0.26]),
      head, lens,
    ]
  }

  private func checkeredRug(_ piece: GenzPiece) -> [Entity] {
    var light: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    var dark: [(centre: SIMD3<Float>, size: SIMD3<Float>)] = []
    for column in 0..<8 {
      for row in 0..<7 {
        let tile = (
          centre: GenzRoomPoint(Float(column) * 0.5 + 0.25, Float(row) * 0.5 + 0.25, 0.015).scene,
          size: SIMD3<Float>(0.5, 0.03, 0.5)
        )
        if (column + row) % 2 == 0 { dark.append(tile) } else { light.append(tile) }
      }
    }
    return [
      part(boxes("checker light", light), matte(piece.slot(0))),
      part(boxes("checker dark", dark), matte(piece.slot(1))),
    ]
  }

  private func phone(_ piece: GenzPiece) -> [Entity] {
    [
      block(0, 0, 0, 0.34, 0.2, 0.025, matte(piece.slot(0))),
      block(0.02, 0.02, 0.025, 0.3, 0.16, 0.006, glow(piece.slot(1))),
      block(0.15, 0.2, 0.004, 0.03, 0.5, 0.02, matte(piece.slot(2))),
    ]
  }

  private func sneakers(_ piece: GenzPiece) -> [Entity] {
    let upper = matte(piece.slot(0))
    let sole = matte(piece.slot(1))
    var parts: [Entity] = []
    for (x, y) in [(Float(0), Float(0)), (0.1, 0.5)] {
      parts.append(block(x, y, 0, 0.75, 0.3, 0.06, sole))
      parts.append(block(x, y, 0.06, 0.75, 0.3, 0.07, upper))
      parts.append(block(x + 0.05, y + 0.03, 0.13, 0.42, 0.24, 0.13, upper))
    }
    return parts
  }

  private func hoodiePile(_ piece: GenzPiece) -> [Entity] {
    [
      part(
        prism(sides: 7, radius: 0.7, top: 0.55, height: 0.25), matte(piece.slot(0)),
        at: GenzRoomPoint(0.7, 0.7, 0).scene),
      part(
        prism(sides: 6, radius: 0.45, top: 0.3, height: 0.22), matte(piece.slot(1)),
        at: GenzRoomPoint(0.95, 0.9, 0.12).scene),
    ]
  }

  private func monstera(_ piece: GenzPiece) -> [Entity] {
    let leaf = matte(piece.slot(1))
    let vein = matte(piece.slot(2))
    let centre = GenzRoomPoint(1.2, 1.2, 0)
    var parts: [Entity] = [
      part(
        prism(sides: 8, radius: 0.5, top: 0.58, height: 0.8), matte(piece.slot(0)),
        at: centre.scene)
    ]
    let shape = slab(
      "monstera leaf", outline: [[0, 0], [0.42, 0.8], [0, 1.45], [-0.42, 0.8]], depth: 0.03)
    let stems: [(turn: Float, lean: Float, length: Float)] = [
      (0.2, 0.5, 1.3), (1.4, 0.35, 1.5), (2.6, 0.55, 1.35), (3.7, 0.4, 1.45),
      (4.8, 0.6, 1.2), (5.7, 0.3, 1.55),
    ]
    for (index, stem) in stems.enumerated() {
      let turn = simd_quatf(angle: stem.turn, axis: [0, 1, 0])
      let lean = simd_quatf(angle: stem.lean, axis: [1, 0, 0])
      let model = part(
        shape, index.isMultiple(of: 2) ? leaf : vein, at: centre.scene + [0, 0.8, 0],
        turn: turn * lean)
      model.scale = .one * stem.length / 1.45
      parts.append(model)
    }
    return parts
  }

  /// The print is a separate part named for the poster texture.
  private func posterFrame(_ piece: GenzPiece) -> [Entity] {
    let print = block(0.05, 0, 0.05, 0.95, 0.03, 1.8, matte(piece.slot(1)))
    print.name = GenzRoom.posterName
    return [block(0, 0.01, 0, 1.05, 0.02, 1.9, matte(piece.slot(0))), print]
  }

  private func daybed(_ piece: GenzPiece) -> [Entity] {
    let frame = matte(piece.slot(0))
    let throwColour = matte(piece.slot(2))
    return [
      block(0, 0, 0, 6.6, 2.4, 0.45, frame),
      block(0.06, 0.04, 0.45, 6.48, 2.3, 0.34, matte(piece.slot(1))),
      block(0.3, 0.06, 0.79, 1.3, 0.45, 0.55, matte(piece.slot(1).shaded(0.45))),
      block(1.8, 0.06, 0.79, 1.3, 0.45, 0.5, matte(piece.slot(0).shaded(0.4))),
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
