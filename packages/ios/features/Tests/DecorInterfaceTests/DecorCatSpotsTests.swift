import Testing

@testable import DecorInterface

@Suite struct DecorCatSpotsTests {
  private func layout(_ spots: [Placement]) -> DecorLayout {
    DecorLayout(placements: spots, stored: [])
  }

  @Test func theCatalogSaysWhatTheCatDoesWithAPiece() {
    #expect(DecorItem.item(shopID: "armchair")?.cat == .sofa)
    #expect(DecorItem.item(shopID: "windowseat")?.cat == .windowSeat)
    #expect(DecorItem.item(shopID: "scratchpost")?.cat == .post)
    #expect(DecorItem.item(shopID: "catbed")?.cat == .catBed)
    #expect(DecorItem.item(shopID: "box")?.cat == .crate)
    #expect(DecorItem.item(shopID: "lamp")?.cat == nil)
  }

  @Test func aPlacedSofaGivesASpotBesideItAndATopToSitOn() {
    let sofa = Placement(item: "armchair", surface: .floor, u: -2, v: 6)
    let plans = layout([sofa]).catSpots()
    #expect(plans.count == 1)
    let plan = plans[0]
    #expect(plan.use == .sofa && plan.item == "armchair")
    #expect(plan.top?.point.x == DecorGrid.metres(-2))
    #expect((plan.top?.height ?? 0) > 0.1)
    let occupancy = layout([sofa]).occupancy()
    #expect(!occupancy.isBlocked(at: plan.approach))
    #expect(occupancy.connects(from: layout([sofa]).spawn(), to: [plan.approach]))
  }

  @Test func aPostIsStoodBesideAndNotClimbed() {
    let post = Placement(item: "scratchpost", surface: .floor, u: -2, v: 6)
    let plan = layout([post]).catSpots().first
    #expect(plan?.use == .post)
    #expect(plan?.top == nil)
  }

  @Test func oneSpotForEachUseTheFirstByName() {
    let first = Placement(item: "beanbag", surface: .floor, u: -2, v: 7)
    let second = Placement(item: "armchair", surface: .floor, u: -2, v: 6)
    let plans = layout([first, second]).catSpots()
    #expect(plans.map(\.item) == ["armchair"])
  }

  @Test func piecesTheCatHasNoUseForAndWallPiecesGiveNothing() {
    #expect(layout([Placement(item: "lamp", surface: .floor, u: -5, v: -5)]).catSpots().isEmpty)
    #expect(layout([Placement(item: "print", surface: .backWall, u: 6)]).catSpots().isEmpty)
    #expect(layout([]).catSpots().isEmpty)
  }

  @Test func aPieceShutOffFromHerBedGivesNoSpot() {
    // A wall of tall pieces along the strip in front of the bed.
    let sofa = Placement(item: "armchair", surface: .floor, u: -2, v: 6)
    let shut = DecorLayout(
      placements: [sofa]
        + (-9...9).filter { $0 < -5 || $0 > 1 }.map {
          Placement(item: $0.isMultiple(of: 2) ? "bookcase" : "tower", surface: .floor, u: $0, v: 4)
        },
      stored: [])
    let plans = shut.catSpots()
    if let plan = plans.first {
      let occupancy = shut.occupancy()
      #expect(occupancy.connects(from: shut.spawn(), to: [plan.approach]))
    }
  }
}

@Suite struct DecorCatSpotsInRoomTests {
  /// Every seat and approach the cat is sent to stays inside the room, above the floor, and is a number.
  @Test func everyPlacementOfEverySeatGivesSpotsInsideTheRoom() {
    let seats = ["armchair", "windowseat", "scratchpost", "catbed", "box", "beanbag", "cattree"]
    let reach = Double(Occupancy.reach + 1) * DecorGrid.step
    for item in seats {
      for u in stride(from: -Occupancy.reach, through: Occupancy.reach, by: 3) {
        for v in stride(from: -Occupancy.reach, through: Occupancy.reach, by: 3) {
          let layout = DecorLayout(
            placements: [Placement(item: item, surface: .floor, u: u, v: v)], stored: [])
          let occupancy = layout.occupancy()
          for plan in layout.catSpots() {
            var points = [plan.approach]
            if let top = plan.top {
              points.append(top.point)
              #expect(top.height.isFinite && top.height > 0 && top.height < 0.8)
            }
            points += occupancy.route(from: DecorRoom.home.spawn, to: plan.approach) ?? []
            for point in points {
              #expect(point.x.isFinite && point.z.isFinite)
              #expect(abs(point.x) <= reach && abs(point.z) <= reach)
            }
          }
        }
      }
    }
  }
}
