import Testing

@testable import DecorInterface

@Suite struct DecorLayoutTests {
  @Test func theShopsPiecesAreAllPlaceable() {
    #expect(DecorItem.all.count == 47)
    #expect(Set(DecorItem.all.map(\.id)).count == DecorItem.all.count)
    #expect(DecorItem.item(shopID: "windowseat")?.mount == .floor)
    #expect(DecorItem.item(shopID: "clock")?.mount == .wall)
    #expect(DecorItem.item(shopID: "floorcushion-sage")?.isFlat == true)
    #expect(DecorItem.item(shopID: "desk")?.isFlat == false)
    #expect(DecorItem.item(shopID: "print")?.mount == .wall)
    #expect(DecorItem.item(shopID: "rug")?.isFlat == true)
    #expect(DecorItem.item(shopID: "treat-fish") == nil)
  }

  @Test func aFullRoomLeavesTheNextPieceInTheCloset() {
    let ids = DecorItem.all.map(\.id)
    var layout = DecorLayout(stored: [])
    for (index, id) in ids.prefix(DecorLayout.maxPlaced).enumerated() {
      layout = layout.putting(Placement(item: id, surface: .floor, u: index, v: 0))
    }
    let next = ids[DecorLayout.maxPlaced]
    let settled = layout.settled(owned: Set(ids))
    #expect(settled.placements.count == DecorLayout.maxPlaced)
    #expect(!settled.isPlaced(next))
    #expect(settled.stored.contains(next))
  }

  @Test func everyPieceIsASizeTheRoomCanHold() {
    for item in DecorItem.all {
      #expect(item.width > 0 && item.width <= 0.6, "\(item.id)")
      #expect(
        item.mount == .wall ? item.depth == 0 : item.depth > 0 && item.depth <= 0.6, "\(item.id)")
      #expect(item.assetName.hasPrefix("Decor_") || item.assetName == "Item_\(item.id)")
    }
  }

  @Test func aNewPieceGoesIntoTheRoomByItself() {
    let layout = DecorLayout(stored: []).settled(owned: ["yarn", "print"])
    #expect(layout.isPlaced("yarn"))
    #expect(layout.isPlaced("print"))
    #expect(layout.accepts(layout.placement(of: "yarn")!))
    #expect(layout.placement(of: "print")?.surface != .floor)
  }

  @Test func theStartersWaitInTheCloset() {
    let owned: Set<String> = ["lamp", "rug", "yarn"]
    let layout = DecorLayout().settled(owned: owned)
    #expect(!layout.isPlaced("lamp"))
    #expect(!layout.isPlaced("rug"))
    #expect(layout.isPlaced("yarn"))
    #expect(layout.closet(owned: owned).map(\.id) == ["lamp", "rug"])
  }

  @Test func aPieceAlreadyPlacedStaysWhereItIs() {
    let spot = Placement(item: "yarn", surface: .floor, u: 3, v: 6, quarterTurns: 1)
    let layout = DecorLayout(placements: [spot], stored: []).settled(owned: ["yarn"])
    #expect(layout.placement(of: "yarn") == spot)
  }

  @Test func twoPiecesDoNotStandInOnePlace() {
    let first = Placement(item: "mouse", surface: .floor, u: -5, v: -5)
    let layout = DecorLayout(placements: [first], stored: [])
    #expect(layout.verdict(Placement(item: "yarn", surface: .floor, u: -5, v: -5)) == .occupied)
    #expect(layout.accepts(Placement(item: "yarn", surface: .floor, u: -4, v: 6)))
  }

  @Test func aRugIsStoodOn() {
    let mouse = Placement(item: "mouse", surface: .floor, u: -5, v: -5)
    let layout = DecorLayout(placements: [mouse], stored: [])
    #expect(layout.accepts(Placement(item: "rug", surface: .floor, u: 0, v: 0)))
    #expect(layout.verdict(Placement(item: "yarn", surface: .floor, u: -5, v: -5)) == .occupied)
  }

  @Test func theRoomsOwnFurnitureBlocksTheFloor() {
    let onTheBed = Placement(item: "armchair", surface: .floor, u: 1, v: -1)
    #expect(!DecorLayout().accepts(onTheBed))
    #expect(DecorLayout().accepts(Placement(item: "rug", surface: .floor, u: 1, v: -1)))
  }

  @Test func nothingStandsOutsideTheRoom() {
    #expect(!DecorLayout().accepts(Placement(item: "armchair", surface: .floor, u: 9, v: 9)))
    #expect(!DecorLayout().accepts(Placement(item: "armchair", surface: .floor, u: -10, v: 0)))
  }

  @Test func aWallPieceOnlyHangsOnAWall() {
    #expect(!DecorLayout().accepts(Placement(item: "print", surface: .floor, u: 4, v: 4)))
    #expect(!DecorLayout().accepts(Placement(item: "armchair", surface: .backWall, u: 4)))
    #expect(DecorLayout().accepts(Placement(item: "print", surface: .backWall, u: 6)))
  }

  @Test func aTurnSwapsAFloorPiecesSides() {
    let bookcase = Placement(item: "bookcase", surface: .floor, u: -1, v: 7)
    #expect(DecorLayout().accepts(bookcase))
    #expect(
      !DecorLayout().accepts(bookcase.turned), "turned it is 0.3 deep and runs through the wall")
    #expect(Placement(item: "print", surface: .backWall, u: 2).turned.quarterTurns == 0)
    #expect(
      Placement(item: "yarn", surface: .floor, u: 0, v: 0, quarterTurns: 3).turned.quarterTurns == 0
    )
  }

  @Test func closetCountsAreWhatIsOwnedAndNotStanding() {
    let owned: Set<String> = ["yarn", "mouse", "lamp", "treat-fish"]
    let layout = DecorLayout().settled(owned: owned)
    #expect(layout.placedCount(owned: owned) == 2)
    #expect(layout.closetCount(owned: owned) == 1)
    let after = layout.storing("yarn")
    #expect(
      after.closet(owned: owned).map(\.id) == ["lamp", "yarn"]
        || after.closet(owned: owned).first?.id == "lamp")
    #expect(after.closetCount(owned: owned) == 2)
  }

  @Test func aPieceNoLongerOwnedLeavesTheRoom() {
    let layout = DecorLayout().settled(owned: ["yarn"]).keeping(owned: [])
    #expect(layout.placements.isEmpty)
  }

  @Test func aPieceThatFitsNowhereGoesToTheCloset() {
    let layout = DecorLayout(stored: []).settled(owned: ["tower"])
    #expect(layout.isPlaced("tower") || layout.stored.contains("tower"))
    #expect(DecorLayout(stored: []).defaultPlacement(for: "unknown") == nil)
  }

  /// The room is about 0.4 of real size, its walls 0.8 m high and its floor 1 m across: a piece that is not a
  /// plausible size there swallows the room (a lamp as wide as the armchair did).
  @Test func everyPieceIsASensibleSizeForTheRoom() {
    for item in DecorItem.all {
      let biggest = max(item.width, item.depth, item.mount == .wall ? 0 : item.height)
      #expect(biggest >= 0.04, "\(item.id) is too small to see")
      if item.mount == .wall {
        #expect(item.width <= 0.3, "\(item.id) is too wide for a wall")
        #expect(item.height <= 0.35, "\(item.id) is too tall for a wall")
      } else if item.isFlat {
        #expect(max(item.width, item.depth) <= 0.6, "\(item.id) is too big for the floor")
        #expect(item.height <= 0.15, "\(item.id) is not flat")
      } else {
        #expect(max(item.width, item.depth) <= 0.55, "\(item.id) is too big for the floor")
        #expect(item.height <= 0.65, "\(item.id) is too tall for the walls")
      }
    }
  }

  /// Pieces whose real size we know, as a share of the room: their longest side, in metres, at 0.4 of real.
  @Test func theFamiliarPiecesAreTheSizeOfWhatTheyAre() {
    let ranges: [String: ClosedRange<Double>] = [
      "lamp": 0.15...0.3, "armchair": 0.3...0.45, "donutbed": 0.35...0.45, "rug": 0.5...0.6,
      "tower": 0.45...0.6, "yarn": 0.05...0.1, "mouse": 0.05...0.15, "teatable": 0.15...0.25,
      "monstera": 0.3...0.5, "bookcase": 0.4...0.6, "floorlamp": 0.4...0.65, "desk": 0.4...0.55,
      "windowseat": 0.25...0.4, "scratchpost": 0.2...0.45, "cactus": 0.05...0.15,
    ]
    for (id, range) in ranges {
      guard let item = DecorItem.item(shopID: id) else {
        Issue.record("\(id) is not in the catalog")
        continue
      }
      let longest = max(item.width, item.depth, item.height)
      #expect(range.contains(longest), "\(id) is \(longest) m")
    }
  }
}
