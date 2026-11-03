import Pet
import Testing

@testable import PetSceneReality

/// The generated props pilot: the Labs switch swaps Window Seat's hand-made pieces for the
/// generated ones at the same spots, sized from their real measures, and the cat can lie on the
/// soft ones.
@MainActor
@Suite struct GenzIdolPropsTests {
  @Test func everyPropHasItsOwnKindWithNoColourSlots() {
    #expect(Set(IdolProp.allCases.map(\.kind)).count == IdolProp.allCases.count)
    for prop in IdolProp.allCases {
      #expect(prop.kind.idol == prop)
      #expect(prop.kind.slotNames.isEmpty)
      #expect(prop.kind.standardSlots.isEmpty)
      #expect(!prop.kind.title.isEmpty)
      #expect(prop.modelName == "Idol_\(prop.rawValue)")
    }
  }

  @Test func aPropIsItsRealSizeInRoomUnits() {
    let lamp = GenzPiece.Kind.idolFloorLamp.size
    #expect(abs(lamp.z - 1.5 * GenzRoomPoint.perMetre) < 1e-4)
    let mugs = GenzPiece.Kind.idolMugs.size
    // About as tall as the hand-made mugs.
    #expect(abs(mugs.z - GenzPiece.Kind.mugs.size.z) < 0.05)
  }

  @Test func theSwitchSwapsWindowSeatsPiecesAndLeavesTheFirstSetAlone() {
    let made = GenzLayout.of(.cosyNook)
    let idol = GenzLayout.of(.cosyNook, idolProps: true)
    #expect(idol.key != made.key)
    #expect(idol.key.idolProps)
    let kinds = Set(idol.pieces.map(\.piece.kind))
    for gone in [GenzPiece.Kind.patternRug, .leafyPlant, .catBed, .knitPouf, .mugs, .cardigan] {
      #expect(!kinds.contains(gone), "\(gone)")
    }
    // The pilot's props, all but the record player, which only the retro set has.
    let pilot: Set<GenzPiece.Kind> = [
      .idolBeanBag, .idolFloorLamp, .idolThrow, .idolMonstera, .idolCactus, .idolBooks, .idolMugs,
      .idolStringLights, .idolRug, .idolCatBed,
    ]
    #expect(pilot.isSubset(of: kinds))
    let retro = GenzLayout.of(.retroDen, idolProps: true)
    #expect(retro.pieces.contains { $0.piece.kind == .idolRecordPlayer })
    #expect(retro.pieces.contains { $0.piece.kind == .idolBeanBag })
    // The lamp that lights the room stays the hand-made one.
    #expect(kinds.contains(.pleatedLamp))
    // The first simple set is as it was.
    let first = GenzLayout.of(.original, idolProps: true)
    #expect(!first.pieces.contains { $0.piece.kind.idol != nil })
  }

  @Test func theCatCanLieOnTheThrowAndTheBooksOnTheSeat() throws {
    let layout = GenzLayout.of(.cosyNook, idolProps: true)
    let tops = layout.catObstacles.filter(\.sitOnTop)
    #expect(tops.count == 2)
    let mugs = try #require(layout.pieces.first { $0.piece.kind == .idolMugs })
    let blocking = layout.catObstacles.filter { !$0.sitOnTop && !$0.builtIn }
    #expect(blocking.contains { $0.box.contains([mugs.centre.x, mugs.centre.y]) })
  }

  @Test func aPropWithoutItsModelIsEmptyAndTheRoomStillBuilds() {
    let kit = GenzKit()
    for prop in IdolProp.allCases {
      #expect(kit.build(GenzPiece(prop.kind)).children.isEmpty)
    }
  }

  @Test func aShopItemFindsItsKind() {
    for prop in IdolProp.allCases {
      #expect(GenzPiece.Kind(shopItem: "furniture-idol-\(prop.rawValue)") == prop.kind)
    }
    #expect(GenzPiece.Kind(shopItem: "furniture-armchair") == nil)
    #expect(GenzPiece.Kind(shopItem: "furniture-idol-nothing") == nil)
  }

  @Test func hungThingsGoOnAWallAndOthersStandSomewhere() {
    for prop in IdolProp.allCases {
      #expect(!prop.surfaces.isEmpty, "\(prop)")
      if prop.surfaces.contains(.wall) { #expect(prop.surfaces == [.wall], "\(prop)") }
      #expect(prop.metres.x > 0 && prop.metres.y > 0 && prop.metres.z > 0, "\(prop)")
    }
    #expect(IdolProp.clock.surfaces == [.wall])
    #expect(IdolProp.teaSet.surfaces.contains(.top))
    #expect(IdolProp.beanbag.surfaces == [.floor])
  }
}
