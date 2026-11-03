import Pet
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct GenzCatPathTests {
  private static var layouts: [GenzLayout] {
    [RoomStyle.windowSeat, .sunsetLamp].flatMap { style in
      RoomFurniture.allCases.compactMap { GenzLayout.of(style, furniture: $0) }
    }
  }

  @Test func theCatsPlaceIsClearOfWhatStandsOnItsTop() {
    for layout in Self.layouts {
      let home = SIMD2(layout.cat.spot.x, layout.cat.spot.y)
      #expect(!layout.catClutter.contains { $0.contains(home) }, "\(layout.key)")
    }
  }

  @Test func nowhereTheCatIsSentIsAmongClutter() throws {
    for layout in Self.layouts {
      let surface = try #require(layout.catSurface)
      for x in stride(from: surface.min.x, through: surface.max.x, by: 0.2) {
        for y in stride(from: surface.min.y, through: surface.max.y, by: 0.2) {
          let spot = layout.onCatSurface([x, y])
          #expect(
            !layout.catClutter.contains { $0.contains(spot) }, "\(layout.key) sends it to \(spot)")
        }
      }
    }
  }

  @Test func aWalkAlongTheSeatStopsShortOfTheCardigan() throws {
    let layout = try #require(GenzLayout.of(.windowSeat, furniture: .cosyNook))
    let cardigan = try #require(layout.pieces.first { $0.piece.kind == .cardigan })
    let home = SIMD2(layout.cat.spot.x, layout.cat.spot.y)
    let reach = layout.catReach(from: home, to: [0.9, home.y])
    let cardiganEnd = cardigan.centre.x + cardigan.piece.kind.size.x / 2
    #expect(reach.x > cardiganEnd + layout.cat.length * 0.4)
    #expect(reach.x < home.x)
    let legs = [CatTrip.Leg.walk(to: [0.9, home.y], speed: 1)].clear(of: layout, from: home)
    guard case .walk(let to, _, _) = legs.first else {
      Issue.record("the walk is kept")
      return
    }
    #expect(to == reach)
  }

  @Test func thePlantOnTheDaybedIsInTheWayButThePhoneIsNot() throws {
    let layout = try #require(GenzLayout.of(.windowSeat, furniture: .original))
    let plant = try #require(layout.pieces.first { $0.piece.kind == .snakePlant })
    let phone = try #require(layout.pieces.first { $0.piece.kind == .phoneOnCharger })
    #expect(layout.catClutter.contains { $0.contains([plant.centre.x, plant.centre.y]) })
    #expect(!layout.catClutter.contains { $0.contains([phone.centre.x, phone.centre.y]) })
  }
}
