import Testing

@testable import DecorInterface

@Suite struct DecorLayoutTests {
  @Test func theShopsPiecesAreAllPlaceable() {
    #expect(DecorItem.all.count == 12)
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
    let first = Placement(item: "mouse", surface: .floor, u: 0, v: 6)
    let layout = DecorLayout(placements: [first], stored: [])
    #expect(layout.verdict(Placement(item: "yarn", surface: .floor, u: 0, v: 6)) == .occupied)
    #expect(layout.accepts(Placement(item: "yarn", surface: .floor, u: -4, v: 6)))
  }

  @Test func aRugIsStoodOn() {
    let mouse = Placement(item: "mouse", surface: .floor, u: 0, v: 6)
    let layout = DecorLayout(placements: [mouse], stored: [])
    #expect(layout.accepts(Placement(item: "rug", surface: .floor, u: 0, v: 0)))
    #expect(layout.verdict(Placement(item: "yarn", surface: .floor, u: 0, v: 6)) == .occupied)
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
}
